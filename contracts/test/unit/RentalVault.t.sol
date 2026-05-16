// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {GameItems} from "../../src/tokens/GameItems.sol";
import {GameToken} from "../../src/tokens/GameToken.sol";
import {RentalVault} from "../../src/vaults/RentalVault.sol";

contract RentalVaultUnitTest is Test {
    GameItems internal items;
    GameToken internal token;
    RentalVault internal rental;
    address internal admin = address(this);
    address internal owner = address(0xAA);
    address internal renter = address(0xBB);
    address internal feeRec = address(0xFEE);

    function setUp() public {
        GameItems impl = new GameItems();
        bytes memory data = abi.encodeCall(GameItems.initialize, (admin, "ipfs://t/{id}.json"));
        items = GameItems(address(new ERC1967Proxy(address(impl), data)));
        items.grantRole(items.MINTER_ROLE(), admin);
        token = new GameToken(admin, admin, 1_000_000e18);
        rental = new RentalVault(admin, feeRec);

        items.mint(owner, 5000, 10, ""); // equipment id
        token.transfer(renter, 1000e18);
    }

    function _list(uint256 amount, uint256 pricePerSec, uint64 minD, uint64 maxD)
        internal
        returns (uint256 id)
    {
        vm.startPrank(owner);
        items.setApprovalForAll(address(rental), true);
        id = rental.list(address(items), 5000, amount, address(token), pricePerSec, minD, maxD);
        vm.stopPrank();
    }

    function test_list_escrowsItems() public {
        _list(3, 1e15, 60, 7 days);
        assertEq(items.balanceOf(address(rental), 5000), 3);
        assertEq(items.balanceOf(owner, 5000), 7);
    }

    function test_cancel_returnsItems() public {
        uint256 id = _list(3, 1e15, 60, 7 days);
        vm.prank(owner);
        rental.cancel(id);
        assertEq(items.balanceOf(owner, 5000), 10);
    }

    function test_rent_paysAndForwards() public {
        uint256 id = _list(2, 1e15, 60, 7 days);
        vm.startPrank(renter);
        token.approve(address(rental), type(uint256).max);
        rental.rent(id, 1 hours);
        vm.stopPrank();
        assertEq(items.balanceOf(renter, 5000), 2);
        // Owner accrued (cost - 2% fee)
        uint256 totalCost = uint256(3600) * 1e15;
        uint256 fee = totalCost * 200 / 10_000;
        assertEq(rental.payoutOf(owner, address(token)), totalCost - fee);
        assertEq(rental.payoutOf(feeRec, address(token)), fee);
    }

    function test_rent_revertsOnInvalidDuration() public {
        uint256 id = _list(2, 1e15, 60, 7 days);
        vm.startPrank(renter);
        token.approve(address(rental), type(uint256).max);
        vm.expectRevert(RentalVault.InvalidDuration.selector);
        rental.rent(id, 1);
        vm.stopPrank();
    }

    function test_endRental_returnsToOwner() public {
        uint256 id = _list(2, 1e15, 60, 7 days);
        vm.startPrank(renter);
        token.approve(address(rental), type(uint256).max);
        rental.rent(id, 1 hours);
        items.setApprovalForAll(address(rental), true);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 hours + 1);
        rental.endRental(id);
        assertEq(items.balanceOf(owner, 5000), 8);
    }

    function test_claimPayout_pullsFunds() public {
        uint256 id = _list(2, 1e15, 60, 7 days);
        vm.startPrank(renter);
        token.approve(address(rental), type(uint256).max);
        rental.rent(id, 1 hours);
        vm.stopPrank();

        uint256 ownerBalBefore = token.balanceOf(owner);
        vm.prank(owner);
        rental.claimPayout(address(token));
        assertGt(token.balanceOf(owner) - ownerBalBefore, 0);
    }

    function test_setProtocolFee_revertsAboveCap() public {
        vm.expectRevert(RentalVault.InvalidFee.selector);
        rental.setProtocolFeeBps(1001);
    }

    function test_pause_blocksList() public {
        rental.pause();
        vm.startPrank(owner);
        items.setApprovalForAll(address(rental), true);
        vm.expectRevert();
        rental.list(address(items), 5000, 1, address(token), 1e15, 60, 7 days);
        vm.stopPrank();
    }

    function test_cancel_revertsForNonOwner() public {
        uint256 id = _list(2, 1e15, 60, 7 days);
        vm.prank(renter);
        vm.expectRevert(RentalVault.NotOwner.selector);
        rental.cancel(id);
    }

    function test_endRental_revertsBeforeExpiry() public {
        uint256 id = _list(2, 1e15, 60, 7 days);
        vm.startPrank(renter);
        token.approve(address(rental), type(uint256).max);
        rental.rent(id, 1 hours);
        vm.stopPrank();
        vm.expectRevert(RentalVault.RentalActive.selector);
        rental.endRental(id);
    }
}
