// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {YulMath} from "../libs/YulMath.sol";

/// @title ResourceAMM
/// @notice Constant-product AMM (x·y=k) for two fungible game resources.
/// @dev Built from scratch (NOT a Uniswap fork), following the syllabus requirement.
///      - 0.30 % fee, accrued to LPs (no protocol cut at v1).
///      - LP shares are this very contract (ERC-20).
///      - Slippage protection on `swap`/`removeLiquidity` (`min*Out` arguments).
///      - Reentrancy guard on every state-mutating external function.
///      - First-deposit MINIMUM_LIQUIDITY is locked (Uniswap-style inflation-attack guard).
///      - Uses `YulMath.sqrt` for the initial-mint LP amount and `mulDiv` for price math.
///
/// External dependencies: only `IERC20`/`SafeERC20` from OZ — the AMM logic itself is
/// self-contained.
contract ResourceAMM is ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant MINIMUM_LIQUIDITY = 1000;
    uint256 public constant FEE_NUMERATOR = 997; // 0.30 % fee → 1000-3
    uint256 public constant FEE_DENOMINATOR = 1000;

    IERC20 public immutable token0;
    IERC20 public immutable token1;

    uint112 private _reserve0;
    uint112 private _reserve1;
    uint32 private _blockTimestampLast; // optional analytics, not used for pricing

    /// @notice Cumulative product of (reserve0 * reserve1) immediately after the last successful
    ///         swap. Used in invariant tests to prove that k never decreases.
    uint256 public kLast;

    event Mint(
        address indexed sender,
        address indexed to,
        uint256 amount0,
        uint256 amount1,
        uint256 liquidity
    );
    event Burn(
        address indexed sender,
        address indexed to,
        uint256 amount0,
        uint256 amount1,
        uint256 liquidity
    );
    event Swap(
        address indexed sender,
        address indexed to,
        address tokenIn,
        uint256 amountIn,
        uint256 amountOut
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    error InsufficientInputAmount();
    error InsufficientOutputAmount();
    error InsufficientLiquidity();
    error InsufficientLiquidityMinted();
    error InsufficientLiquidityBurned();
    error InvalidToken();
    error SlippageExceeded();
    error KInvariantViolated();
    error Overflow();

    constructor(IERC20 _token0, IERC20 _token1)
        ERC20(_lpName(_token0, _token1), _lpSymbol(_token0, _token1))
    {
        require(address(_token0) != address(_token1), "ResourceAMM: identical tokens");
        require(
            address(_token0) != address(0) && address(_token1) != address(0), "ResourceAMM: zero"
        );
        // Sort so token0 < token1 deterministically — caller may pass them in any order.
        if (address(_token0) < address(_token1)) {
            token0 = _token0;
            token1 = _token1;
        } else {
            token0 = _token1;
            token1 = _token0;
        }
    }

    // -----------------------------------------------------------------------
    // Views
    // -----------------------------------------------------------------------

    function getReserves() public view returns (uint112 r0, uint112 r1, uint32 ts) {
        return (_reserve0, _reserve1, _blockTimestampLast);
    }

    /// @notice Pure pricing helper. amountOut = (amountIn * 997 * reserveOut) / (reserveIn*1000 + amountIn*997)
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        public
        pure
        returns (uint256 amountOut)
    {
        if (amountIn == 0) revert InsufficientInputAmount();
        if (reserveIn == 0 || reserveOut == 0) revert InsufficientLiquidity();
        uint256 amountInWithFee = amountIn * FEE_NUMERATOR;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * FEE_DENOMINATOR + amountInWithFee;
        amountOut = numerator / denominator;
    }

    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB)
        public
        pure
        returns (uint256 amountB)
    {
        if (amountA == 0) revert InsufficientInputAmount();
        if (reserveA == 0 || reserveB == 0) revert InsufficientLiquidity();
        return YulMath.mulDiv(amountA, reserveB, reserveA);
    }

    // -----------------------------------------------------------------------
    // Liquidity provisioning
    // -----------------------------------------------------------------------

    /// @notice Pull-based liquidity add — caller must `approve` the AMM beforehand.
    /// @dev Uses Checks-Effects-Interactions: amounts are computed, LP is minted from pre-checked
    ///      reserves, then the actual token pulls happen (safe because the LP-amount calculation
    ///      uses the contract's pre-transfer reserves, see the `_safeTransferFrom` ordering).
    function addLiquidity(
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address to
    ) external nonReentrant returns (uint256 amount0, uint256 amount1, uint256 liquidity) {
        (uint112 r0, uint112 r1,) = getReserves();
        if (r0 == 0 && r1 == 0) {
            amount0 = amount0Desired;
            amount1 = amount1Desired;
        } else {
            uint256 amount1Optimal = quote(amount0Desired, r0, r1);
            if (amount1Optimal <= amount1Desired) {
                if (amount1Optimal < amount1Min) revert SlippageExceeded();
                amount0 = amount0Desired;
                amount1 = amount1Optimal;
            } else {
                uint256 amount0Optimal = quote(amount1Desired, r1, r0);
                if (amount0Optimal > amount0Desired) revert SlippageExceeded();
                if (amount0Optimal < amount0Min) revert SlippageExceeded();
                amount0 = amount0Optimal;
                amount1 = amount1Desired;
            }
        }

        token0.safeTransferFrom(msg.sender, address(this), amount0);
        token1.safeTransferFrom(msg.sender, address(this), amount1);

        liquidity = _mintLP(to);
        emit Mint(msg.sender, to, amount0, amount1, liquidity);
    }

    function removeLiquidity(uint256 liquidity, uint256 amount0Min, uint256 amount1Min, address to)
        external
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        _transfer(msg.sender, address(this), liquidity);
        (amount0, amount1) = _burnLP(to);
        if (amount0 < amount0Min || amount1 < amount1Min) revert SlippageExceeded();
        emit Burn(msg.sender, to, amount0, amount1, liquidity);
    }

    // -----------------------------------------------------------------------
    // Swap
    // -----------------------------------------------------------------------

    /// @notice Pull-based exact-input swap.
    /// @param tokenIn Either `token0` or `token1`.
    /// @param amountIn Amount of `tokenIn` the user is swapping in.
    /// @param amountOutMin Minimum acceptable output amount (slippage guard).
    /// @param to Recipient of the output tokens.
    function swap(address tokenIn, uint256 amountIn, uint256 amountOutMin, address to)
        external
        nonReentrant
        returns (uint256 amountOut)
    {
        if (amountIn == 0) revert InsufficientInputAmount();
        if (to == address(this) || to == address(0)) revert InvalidToken();

        (IERC20 inToken, IERC20 outToken, uint112 reserveIn, uint112 reserveOut, bool zeroForOne) =
            _resolveDirection(tokenIn);

        amountOut = getAmountOut(amountIn, reserveIn, reserveOut);
        if (amountOut < amountOutMin) revert SlippageExceeded();
        if (amountOut == 0) revert InsufficientOutputAmount();

        // Effects-then-interactions: balances move via SafeERC20 below; we compute & emit first.
        inToken.safeTransferFrom(msg.sender, address(this), amountIn);
        outToken.safeTransfer(to, amountOut);

        // Sync reserves and verify k did not decrease.
        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));

        // Account for fee: reserve_in_after_fee = reserve_in * 1000 - amountIn * 3
        // We assert the constant-product invariant on raw reserves with fee applied.
        if (zeroForOne) {
            uint256 balance0Adj =
                balance0 * FEE_DENOMINATOR - amountIn * (FEE_DENOMINATOR - FEE_NUMERATOR);
            uint256 balance1Adj = balance1 * FEE_DENOMINATOR;
            if (
                balance0Adj * balance1Adj < uint256(reserveIn) * reserveOut * (FEE_DENOMINATOR ** 2)
            ) {
                revert KInvariantViolated();
            }
        } else {
            uint256 balance1Adj =
                balance1 * FEE_DENOMINATOR - amountIn * (FEE_DENOMINATOR - FEE_NUMERATOR);
            uint256 balance0Adj = balance0 * FEE_DENOMINATOR;
            if (
                balance0Adj * balance1Adj < uint256(reserveOut) * reserveIn * (FEE_DENOMINATOR ** 2)
            ) {
                revert KInvariantViolated();
            }
        }

        _update(balance0, balance1);
        kLast = uint256(_reserve0) * uint256(_reserve1);
        emit Swap(msg.sender, to, tokenIn, amountIn, amountOut);
    }

    // -----------------------------------------------------------------------
    // Internal
    // -----------------------------------------------------------------------

    function _resolveDirection(address tokenIn)
        internal
        view
        returns (
            IERC20 inToken,
            IERC20 outToken,
            uint112 reserveIn,
            uint112 reserveOut,
            bool zeroForOne
        )
    {
        if (tokenIn == address(token0)) {
            return (token0, token1, _reserve0, _reserve1, true);
        }
        if (tokenIn == address(token1)) {
            return (token1, token0, _reserve1, _reserve0, false);
        }
        revert InvalidToken();
    }

    function _mintLP(address to) internal returns (uint256 liquidity) {
        (uint112 r0, uint112 r1,) = getReserves();
        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));
        uint256 amount0 = balance0 - r0;
        uint256 amount1 = balance1 - r1;

        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            liquidity = YulMath.sqrt(amount0 * amount1);
            if (liquidity <= MINIMUM_LIQUIDITY) revert InsufficientLiquidityMinted();
            unchecked {
                liquidity -= MINIMUM_LIQUIDITY;
            }
            // Permanently lock MINIMUM_LIQUIDITY at address(0).
            _mint(address(0xdead), MINIMUM_LIQUIDITY);
        } else {
            liquidity = YulMath.min(
                YulMath.mulDiv(amount0, _totalSupply, r0), YulMath.mulDiv(amount1, _totalSupply, r1)
            );
        }
        if (liquidity == 0) revert InsufficientLiquidityMinted();
        _mint(to, liquidity);
        _update(balance0, balance1);
        kLast = uint256(_reserve0) * uint256(_reserve1);
    }

    function _burnLP(address to) internal returns (uint256 amount0, uint256 amount1) {
        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));
        uint256 liquidity = balanceOf(address(this));

        uint256 _totalSupply = totalSupply();
        amount0 = liquidity * balance0 / _totalSupply;
        amount1 = liquidity * balance1 / _totalSupply;
        if (amount0 == 0 || amount1 == 0) revert InsufficientLiquidityBurned();

        _burn(address(this), liquidity);
        token0.safeTransfer(to, amount0);
        token1.safeTransfer(to, amount1);

        balance0 = token0.balanceOf(address(this));
        balance1 = token1.balanceOf(address(this));
        _update(balance0, balance1);
        kLast = uint256(_reserve0) * uint256(_reserve1);
    }

    function _update(uint256 balance0, uint256 balance1) internal {
        if (balance0 > type(uint112).max || balance1 > type(uint112).max) revert Overflow();
        _reserve0 = uint112(balance0);
        _reserve1 = uint112(balance1);
        _blockTimestampLast = uint32(block.timestamp);
        emit Sync(_reserve0, _reserve1);
    }

    // -----------------------------------------------------------------------
    // LP token naming helpers (constructor)
    // -----------------------------------------------------------------------

    function _lpName(IERC20 a, IERC20 b) private view returns (string memory) {
        return string.concat("Aetheria LP ", _safeSymbol(a), "-", _safeSymbol(b));
    }

    function _lpSymbol(IERC20 a, IERC20 b) private view returns (string memory) {
        return string.concat("ALP-", _safeSymbol(a), "-", _safeSymbol(b));
    }

    function _safeSymbol(IERC20 t) private view returns (string memory) {
        try IERC20Metadata(address(t)).symbol() returns (string memory s) {
            return s;
        } catch {
            return "TKN";
        }
    }
}
