// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {GameToken} from "../../src/tokens/GameToken.sol";

contract VotingFuzzTest is Test {
    GameToken internal token;
    address internal admin = address(this);

    function setUp() public {
        token = new GameToken(admin, admin, 100_000_000e18);
    }

    function testFuzz_votingPowerEqualsBalance_afterDelegate(address holder, uint96 amount) public {
        vm.assume(holder != address(0) && holder.code.length == 0 && holder != admin);
        amount = uint96(bound(uint256(amount), 1, 50_000_000e18));
        token.transfer(holder, amount);
        vm.prank(holder);
        token.delegate(holder);
        vm.warp(block.timestamp + 1);
        assertEq(token.getVotes(holder), amount);
    }

    function testFuzz_transferUpdatesVotes(uint96 amount) public {
        amount = uint96(bound(uint256(amount), 1, 1_000_000e18));
        address a = address(0xA1);
        address b = address(0xB1);
        token.transfer(a, amount);
        vm.prank(a);
        token.delegate(a);
        vm.prank(b);
        token.delegate(b);
        vm.warp(block.timestamp + 1);
        uint256 before = token.getVotes(a);
        vm.prank(a);
        token.transfer(b, amount / 2);
        vm.warp(block.timestamp + 1);
        assertEq(token.getVotes(a), before - amount / 2);
        assertEq(token.getVotes(b), amount / 2);
    }
}
