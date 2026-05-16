// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {GameItems} from "../../src/tokens/GameItems.sol";
import {GameItemsV2} from "../../src/upgrades/GameItemsV2.sol";

contract GameItemsV2UnitTest is Test {
    GameItems internal proxy;
    GameItems internal v1Impl;
    GameItemsV2 internal v2Impl;
    address internal admin = address(this);
    address internal alice = address(0xA1);

    function setUp() public {
        v1Impl = new GameItems();
        v2Impl = new GameItemsV2();
        bytes memory data = abi.encodeCall(GameItems.initialize, (admin, "ipfs://t/{id}.json"));
        proxy = GameItems(address(new ERC1967Proxy(address(v1Impl), data)));
        proxy.grantRole(proxy.MINTER_ROLE(), admin);
    }

    function test_storage_preservedAcrossUpgrade() public {
        // Seed state on V1
        proxy.mint(alice, 1, 100, "");

        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;
        uint256[] memory amts = new uint256[](1);
        amts[0] = 5;
        proxy.setRecipe(42, ids, amts, 1000, 1, 0);
        uint256 craftCountBefore = proxy.craftCount(42);
        uint256 balBefore = proxy.balanceOf(alice, 1);

        // Upgrade
        proxy.upgradeToAndCall(address(v2Impl), "");

        // State preserved
        assertEq(proxy.balanceOf(alice, 1), balBefore);
        assertEq(proxy.craftCount(42), craftCountBefore);

        // V2 surface available
        GameItemsV2 v2 = GameItemsV2(address(proxy));
        assertEq(v2.version(), "2.0.0");
        assertEq(v2.craftDiscountBps(), 0); // fresh slot reads 0
    }

    function test_setCraftDiscountBps_andDiscountedCraft() public {
        proxy.upgradeToAndCall(address(v2Impl), "");
        GameItemsV2 v2 = GameItemsV2(address(proxy));

        // Setup: recipe 1 (1 wood -> 1 sword) with fee=10 and a cosmetic proof.
        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;
        uint256[] memory amts = new uint256[](1);
        amts[0] = 1;
        proxy.setRecipe(1, ids, amts, 1000, 1, 10);

        // Mint resources + cosmetic proof to alice.
        proxy.mint(alice, 1, 1000, "");
        proxy.mint(alice, 100_001, 1, ""); // cosmetic id (≥ EQUIPMENT_RANGE_END)

        v2.setCraftDiscountBps(5000); // 50 % discount

        vm.prank(alice);
        v2.craftWithDiscount(1, 1, 100_001);

        // Without discount: 1 wood + 10 wood fee = 11 wood. With 50 % discount on the fee: 1 + 5 = 6 wood burned.
        assertEq(proxy.balanceOf(alice, 1), 1000 - 6);
        assertEq(proxy.balanceOf(alice, 1000), 1);
    }

    function test_craftWithDiscount_revertsWithoutProof() public {
        proxy.upgradeToAndCall(address(v2Impl), "");
        GameItemsV2 v2 = GameItemsV2(address(proxy));
        vm.expectRevert(GameItemsV2.NotMasterCrafter.selector);
        v2.craftWithDiscount(1, 1, 100_001);
    }

    function test_setDiscount_revertsAboveMax() public {
        proxy.upgradeToAndCall(address(v2Impl), "");
        GameItemsV2 v2 = GameItemsV2(address(proxy));
        vm.expectRevert(GameItemsV2.InvalidDiscount.selector);
        v2.setCraftDiscountBps(9001);
    }
}
