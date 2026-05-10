// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ResourceAMM} from "../../src/amm/ResourceAMM.sol";
import {GameToken} from "../../src/tokens/GameToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AMMFuzzTest is Test {
    GameToken internal a;
    GameToken internal b;
    ResourceAMM internal amm;
    address internal owner = address(this);
    address internal trader = address(0xBEEF);

    function setUp() public {
        a = new GameToken(owner, owner, 100_000_000e18);
        b = new GameToken(owner, owner, 100_000_000e18);
        amm = new ResourceAMM(IERC20(address(a)), IERC20(address(b)));
        a.approve(address(amm), type(uint256).max);
        b.approve(address(amm), type(uint256).max);
        amm.addLiquidity(1_000e18, 1_000e18, 0, 0, owner);

        a.transfer(trader, 100_000e18);
        b.transfer(trader, 100_000e18);
    }

    function testFuzz_swap_kNeverDecreases(uint256 amtIn, bool zeroForOne) public {
        amtIn = bound(amtIn, 1e15, 100e18);
        (uint112 r0, uint112 r1,) = amm.getReserves();
        uint256 kBefore = uint256(r0) * uint256(r1);

        vm.startPrank(trader);
        a.approve(address(amm), type(uint256).max);
        b.approve(address(amm), type(uint256).max);
        if (zeroForOne) {
            amm.swap(address(amm.token0()), amtIn, 0, trader);
        } else {
            amm.swap(address(amm.token1()), amtIn, 0, trader);
        }
        vm.stopPrank();

        (r0, r1,) = amm.getReserves();
        uint256 kAfter = uint256(r0) * uint256(r1);
        assertGe(kAfter, kBefore);
    }

    function testFuzz_addLiquidity_returnsLP(uint256 ax, uint256 bx) public {
        ax = bound(ax, 1e15, 1_000e18);
        bx = bound(bx, 1e15, 1_000e18);
        (uint112 r0, uint112 r1,) = amm.getReserves();
        // Match ratio so the optimal computation does not revert on slippage.
        uint256 bxOptimal = ax * uint256(r1) / uint256(r0);
        if (bxOptimal == 0) return;
        a.approve(address(amm), ax);
        b.approve(address(amm), bxOptimal);
        (,, uint256 lp) = amm.addLiquidity(ax, bxOptimal, 0, 0, owner);
        assertGt(lp, 0);
    }

    function testFuzz_quote_isMonotonic(uint256 amtA) public view {
        amtA = bound(amtA, 1, 1_000_000e18);
        uint256 q = amm.quote(amtA, 1_000e18, 2_000e18);
        assertEq(q, amtA * 2);
    }

    function testFuzz_getAmountOut_neverExceedsReserves(uint256 amtIn) public view {
        amtIn = bound(amtIn, 1, 100_000e18);
        uint256 out = amm.getAmountOut(amtIn, 1_000e18, 1_000e18);
        assertLt(out, 1_000e18);
    }
}
