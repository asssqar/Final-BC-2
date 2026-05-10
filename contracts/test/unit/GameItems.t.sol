// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {GameItems} from "../../src/tokens/GameItems.sol";
import {GameItemsV2} from "../../src/upgrades/GameItemsV2.sol";

contract GameItemsUnitTest is Test {
    GameItems internal items;
    GameItems internal impl;
    address internal admin = address(0xA);
    address internal alice = address(0xB);
    address internal bob = address(0xC);

    function setUp() public {
        impl = new GameItems();
        bytes memory data = abi.encodeCall(GameItems.initialize, (admin, "ipfs://t/{id}.json"));
        items = GameItems(address(new ERC1967Proxy(address(impl), data)));
        vm.startPrank(admin);
        items.grantRole(items.MINTER_ROLE(), admin);
        vm.stopPrank();
    }

    function test_initialize_doubleCallReverts() public {
        vm.expectRevert(); // InvalidInitialization
        items.initialize(admin, "x");
    }

    function test_mint_byMinter() public {
        vm.prank(admin);
        items.mint(alice, 1, 100, "");
        assertEq(items.balanceOf(alice, 1), 100);
        assertEq(items.totalSupply(1), 100);
    }

    function test_mint_revertsWhenUnauthorized() public {
        vm.prank(alice);
        vm.expectRevert();
        items.mint(alice, 1, 1, "");
    }

    function test_mint_outOfRangeReverts() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(GameItems.OutOfRange.selector, type(uint256).max));
        items.mint(alice, type(uint256).max, 1, "");
    }

    function test_burn_byHolder() public {
        vm.prank(admin);
        items.mint(alice, 1, 10, "");
        vm.prank(alice);
        items.burn(alice, 1, 4);
        assertEq(items.balanceOf(alice, 1), 6);
    }

    function test_burn_revertsWithoutApproval() public {
        vm.prank(admin);
        items.mint(alice, 1, 10, "");
        vm.prank(bob);
        vm.expectRevert();
        items.burn(alice, 1, 1);
    }

    function test_setRecipe_andCraft() public {
        vm.startPrank(admin);
        items.mint(alice, 1, 100, "");
        items.mint(alice, 2, 100, "");

        uint256[] memory ids = new uint256[](2);
        ids[0] = 1; ids[1] = 2;
        uint256[] memory amts = new uint256[](2);
        amts[0] = 2; amts[1] = 1;
        items.setRecipe(1, ids, amts, 1_000, 1, 5);
        vm.stopPrank();

        vm.prank(alice);
        items.craft(1, 3); // burn 6 wood + 3 iron + 5*3 fee on input[0]=15 → total wood=21
        assertEq(items.balanceOf(alice, 1), 100 - 21);
        assertEq(items.balanceOf(alice, 2), 100 - 3);
        assertEq(items.balanceOf(alice, 1_000), 3);
        assertEq(items.craftCount(1), 3);
    }

    function test_craft_revertsOnInactive() public {
        vm.prank(alice);
        vm.expectRevert(GameItems.RecipeInactive.selector);
        items.craft(99, 1);
    }

    function test_craft_insufficientResource() public {
        vm.startPrank(admin);
        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;
        uint256[] memory amts = new uint256[](1);
        amts[0] = 5;
        items.setRecipe(1, ids, amts, 1_000, 1, 0);
        vm.stopPrank();

        vm.prank(alice);
        vm.expectRevert();
        items.craft(1, 1);
    }

    function test_setRecipe_revertsOnLengthMismatch() public {
        uint256[] memory ids = new uint256[](2);
        uint256[] memory amts = new uint256[](1);
        ids[0] = 1; ids[1] = 2; amts[0] = 1;
        vm.prank(admin);
        vm.expectRevert(GameItems.LengthMismatch.selector);
        items.setRecipe(1, ids, amts, 1_000, 1, 0);
    }

    function test_pause_blocksMint() public {
        vm.prank(admin);
        items.pause();
        vm.prank(admin);
        vm.expectRevert();
        items.mint(alice, 1, 1, "");
    }

    function test_setTokenURI_overrides() public {
        vm.prank(admin);
        items.setTokenURI(1, "ipfs://special");
        assertEq(items.uri(1), "ipfs://special");
    }

    function test_upgrade_toV2() public {
        // Upgrade requires UPGRADER_ROLE; admin already has it.
        GameItemsV2 v2 = new GameItemsV2();
        vm.prank(admin);
        items.upgradeToAndCall(address(v2), "");
        assertEq(GameItemsV2(address(items)).version(), "2.0.0");
    }

    function test_upgrade_revertsForNonUpgrader() public {
        GameItemsV2 v2 = new GameItemsV2();
        vm.prank(alice);
        vm.expectRevert();
        items.upgradeToAndCall(address(v2), "");
    }

    function test_supportsInterface() public view {
        // ERC1155 interfaceId
        assertTrue(items.supportsInterface(0xd9b67a26));
    }

    function test_removeRecipe() public {
        vm.startPrank(admin);
        uint256[] memory ids = new uint256[](1);
        uint256[] memory amts = new uint256[](1);
        ids[0] = 1; amts[0] = 1;
        items.setRecipe(7, ids, amts, 1_000, 1, 0);
        items.removeRecipe(7);
        vm.stopPrank();
        vm.expectRevert(GameItems.RecipeInactive.selector);
        items.craft(7, 1);
    }
}
