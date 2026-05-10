// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {GameToken} from "../../src/tokens/GameToken.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract GameTokenUnitTest is Test {
    GameToken internal token;
    address internal admin = address(0xA11CE);
    address internal user = address(0xB0B);

    function setUp() public {
        token = new GameToken(admin, admin, 1_000e18);
    }

    function test_metadata() public view {
        assertEq(token.name(), "Aetheria");
        assertEq(token.symbol(), "AETH");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 1_000e18);
        assertEq(token.balanceOf(admin), 1_000e18);
    }

    function test_mint_byMinter() public {
        vm.prank(admin);
        token.mint(user, 500e18);
        assertEq(token.balanceOf(user), 500e18);
    }

    function test_mint_revertsWhenNotMinter() public {
        vm.prank(user);
        vm.expectRevert(); // OZ AccessControlUnauthorizedAccount
        token.mint(user, 1);
    }

    function test_mint_revertsAtCap() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(GameToken.CapExceeded.selector, 100_000_001e18, 100_000_000e18));
        token.mint(user, 99_999_002e18);
    }

    function test_burn_reducesSupply() public {
        vm.prank(admin);
        token.transfer(user, 100e18);
        vm.prank(user);
        token.burn(40e18);
        assertEq(token.totalSupply(), 960e18);
        assertEq(token.balanceOf(user), 60e18);
    }

    function test_clock_isTimestamp() public {
        assertEq(token.clock(), uint48(block.timestamp));
        assertEq(token.CLOCK_MODE(), "mode=timestamp");
    }

    function test_delegate_grantsVotingPower() public {
        vm.prank(admin);
        token.delegate(admin);
        vm.warp(block.timestamp + 1);
        assertEq(token.getVotes(admin), 1_000e18);
    }

    function test_permit_works() public {
        // EIP-2612 permit happy path
        uint256 ownerKey = 0xA11CE_BEEF;
        address owner = vm.addr(ownerKey);
        vm.prank(admin);
        token.transfer(owner, 100e18);

        uint256 deadline = block.timestamp + 1 hours;
        bytes32 structHash = keccak256(abi.encode(
            keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
            owner, user, 50e18, token.nonces(owner), deadline
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, digest);
        token.permit(owner, user, 50e18, deadline, v, r, s);
        assertEq(token.allowance(owner, user), 50e18);
    }

    function test_revokeMinter() public {
        vm.prank(admin);
        token.revokeRole(token.MINTER_ROLE(), admin);
        vm.prank(admin);
        vm.expectRevert();
        token.mint(user, 1);
    }

    function test_pastVotes() public {
        vm.prank(admin);
        token.delegate(admin);
        vm.warp(block.timestamp + 100);
        uint256 ts = block.timestamp;
        vm.warp(ts + 1);
        assertEq(token.getPastVotes(admin, ts), 1_000e18);
    }
}
