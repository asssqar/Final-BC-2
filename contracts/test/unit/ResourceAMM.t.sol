// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ResourceAMM} from "../../src/amm/ResourceAMM.sol";
import {GameToken} from "../../src/tokens/GameToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ResourceAMMUnitTest is Test {
    GameToken internal wood;
    GameToken internal iron;
    ResourceAMM internal amm;
    address internal admin = address(this);
    address internal alice = address(0xA1);

    function setUp() public {
        wood = new GameToken(admin, admin, 1_000_000e18);
        iron = new GameToken(admin, admin, 1_000_000e18);
        amm = new ResourceAMM(IERC20(address(wood)), IERC20(address(iron)));
    }

    function _seed(uint256 a, uint256 b) internal returns (uint256 lp) {
        wood.approve(address(amm), a);
        iron.approve(address(amm), b);
        (,, lp) = amm.addLiquidity(a, b, 0, 0, admin);
    }

    function test_constructor_sortsTokens() public view {
        // token0 must be the lower address
        assertTrue(address(amm.token0()) < address(amm.token1()));
    }

    function test_addLiquidity_initialMint() public {
        uint256 lp = _seed(100e18, 100e18);
        // sqrt(100e18*100e18) - 1000
        assertEq(lp, 100e18 - 1000);
        assertEq(amm.totalSupply(), 100e18);
        (uint112 r0, uint112 r1,) = amm.getReserves();
        assertEq(uint256(r0), 100e18);
        assertEq(uint256(r1), 100e18);
    }

    function test_addLiquidity_proportional() public {
        _seed(100e18, 100e18);
        wood.approve(address(amm), 50e18);
        iron.approve(address(amm), 60e18);
        (uint256 a0, uint256 a1, uint256 lp) = amm.addLiquidity(50e18, 60e18, 0, 0, admin);
        // Optimal: a0=50, a1=quote(50, 100, 100) = 50
        assertEq(a0, 50e18);
        assertEq(a1, 50e18);
        assertGt(lp, 0);
    }

    function test_swap_exactInput() public {
        _seed(1000e18, 1000e18);
        wood.transfer(alice, 100e18);
        vm.startPrank(alice);
        wood.approve(address(amm), 100e18);
        uint256 out = amm.swap(address(wood), 100e18, 1, alice);
        vm.stopPrank();

        // expected ≈ (100*997*1000)/(1000*1000+100*997) = 99700e18/1099.7e18 ≈ 90.66e18
        assertGt(out, 90e18);
        assertLt(out, 91e18);
        assertEq(iron.balanceOf(alice), out);
    }

    function test_swap_revertsOnSlippage() public {
        _seed(1000e18, 1000e18);
        wood.approve(address(amm), 100e18);
        vm.expectRevert(ResourceAMM.SlippageExceeded.selector);
        amm.swap(address(wood), 100e18, 999e18, admin);
    }

    function test_swap_revertsOnInvalidToken() public {
        _seed(1000e18, 1000e18);
        vm.expectRevert(ResourceAMM.InvalidToken.selector);
        amm.swap(address(0xdead), 1, 0, admin);
    }

    function test_swap_revertsOnZeroInput() public {
        _seed(1000e18, 1000e18);
        vm.expectRevert(ResourceAMM.InsufficientInputAmount.selector);
        amm.swap(address(wood), 0, 0, admin);
    }

    function test_removeLiquidity_returnsTokens() public {
        uint256 lp = _seed(1000e18, 1000e18);
        amm.transfer(alice, lp / 2);
        vm.startPrank(alice);
        amm.approve(address(amm), lp / 2);
        // For removeLiquidity, the LP tokens are pulled with internal _transfer; user does not need approve(self).
        (uint256 a0, uint256 a1) = amm.removeLiquidity(lp / 2, 0, 0, alice);
        vm.stopPrank();
        assertGt(a0, 0);
        assertGt(a1, 0);
    }

    function test_removeLiquidity_slippageRevert() public {
        uint256 lp = _seed(1000e18, 1000e18);
        vm.expectRevert(ResourceAMM.SlippageExceeded.selector);
        amm.removeLiquidity(lp / 2, type(uint256).max, 0, admin);
    }

    function test_initialMint_revertsBelowMinLiquidity() public {
        wood.approve(address(amm), 10);
        iron.approve(address(amm), 10);
        vm.expectRevert(ResourceAMM.InsufficientLiquidityMinted.selector);
        amm.addLiquidity(10, 10, 0, 0, admin);
    }

    function test_kInvariant_holdsAfterSwap() public {
        _seed(1000e18, 1000e18);
        uint256 kBefore = amm.kLast();
        wood.approve(address(amm), 50e18);
        amm.swap(address(wood), 50e18, 0, admin);
        uint256 kAfter = amm.kLast();
        assertGe(kAfter, kBefore, "k must not decrease");
    }

    function test_quote_works() public view {
        assertEq(amm.quote(100, 1000, 2000), 200);
    }

    function test_getAmountOut_revertsOnZeroReserves() public {
        vm.expectRevert(ResourceAMM.InsufficientLiquidity.selector);
        amm.getAmountOut(1, 0, 0);
    }
}
