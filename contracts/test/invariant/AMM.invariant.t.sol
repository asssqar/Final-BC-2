// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, StdInvariant} from "forge-std/Test.sol";
import {ResourceAMM} from "../../src/amm/ResourceAMM.sol";
import {GameToken} from "../../src/tokens/GameToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Wraps swaps on the AMM to provide an invariant-test handler.
contract AMMHandler is Test {
    ResourceAMM public amm;
    GameToken public a;
    GameToken public b;
    address public actor = makeAddr("actor");

    constructor(ResourceAMM _amm, GameToken _a, GameToken _b) {
        amm = _amm;
        a = _a;
        b = _b;
        deal(address(a), address(this), 1_000_000e18);
        deal(address(b), address(this), 1_000_000e18);
        a.transfer(actor, 1_000_000e18);
        b.transfer(actor, 1_000_000e18);
        vm.startPrank(actor);
        a.approve(address(amm), type(uint256).max);
        b.approve(address(amm), type(uint256).max);
        vm.stopPrank();
    }

    function swapAforB(uint256 amount) external {
        amount = bound(amount, 1e15, 1_000e18);
        vm.prank(actor);
        amm.swap(address(amm.token0()), amount, 0, actor);
    }

    function swapBforA(uint256 amount) external {
        amount = bound(amount, 1e15, 1_000e18);
        vm.prank(actor);
        amm.swap(address(amm.token1()), amount, 0, actor);
    }

    function addLiq(uint256 ax, uint256 bx) external {
        ax = bound(ax, 1e15, 100e18);
        bx = bound(bx, 1e15, 100e18);
        (uint112 r0, uint112 r1,) = amm.getReserves();
        uint256 bxOpt = ax * uint256(r1) / uint256(r0);
        if (bxOpt == 0 || bxOpt > 100e18) return;
        vm.startPrank(actor);
        a.approve(address(amm), ax);
        b.approve(address(amm), bxOpt);
        amm.addLiquidity(ax, bxOpt, 0, 0, actor);
        vm.stopPrank();
    }
}

contract AMMInvariantTest is StdInvariant, Test {
    ResourceAMM internal amm;
    GameToken internal a;
    GameToken internal b;
    AMMHandler internal handler;
    uint256 internal kInitial;

    function setUp() public {
        a = new GameToken(address(this), address(this), 100_000_000e18);
        b = new GameToken(address(this), address(this), 100_000_000e18);
        amm = new ResourceAMM(IERC20(address(a)), IERC20(address(b)));
        a.approve(address(amm), type(uint256).max);
        b.approve(address(amm), type(uint256).max);
        amm.addLiquidity(1_000e18, 1_000e18, 0, 0, address(this));
        kInitial = uint256(1_000e18) * uint256(1_000e18);

        handler = new AMMHandler(amm, a, b);
        // Forward only handler-public functions
        targetContract(address(handler));
    }

    /// @notice The product of reserves is monotonically non-decreasing.
    function invariant_kNeverDecreases() public view {
        (uint112 r0, uint112 r1,) = amm.getReserves();
        uint256 k = uint256(r0) * uint256(r1);
        assertGe(k, kInitial);
    }

    /// @notice Reserves equal the actual ERC-20 balances at all times.
    function invariant_reservesMatchBalances() public view {
        (uint112 r0, uint112 r1,) = amm.getReserves();
        assertEq(uint256(r0), a.balanceOf(address(amm)));
        assertEq(uint256(r1), b.balanceOf(address(amm)));
    }

    /// @notice Total LP supply > 0 once liquidity is seeded.
    function invariant_lpSupplyNonZero() public view {
        assertGt(amm.totalSupply(), 0);
    }
}
