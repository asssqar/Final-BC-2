// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {GameItems} from "../../src/tokens/GameItems.sol";
import {LootBox} from "../../src/loot/LootBox.sol";
import {IGameItems} from "../../src/interfaces/IGameItems.sol";
import {VRFCoordinatorV2_5Mock} from "./VRFCoordinatorV2_5Mock.sol";

contract LootBoxUnitTest is Test {
    GameItems internal items;
    LootBox internal lootBox;
    VRFCoordinatorV2_5Mock internal coord;
    address internal admin = address(this);
    address internal player = address(0xCAFE);
    uint256 internal subId;

    function setUp() public {
        GameItems impl = new GameItems();
        items = GameItems(address(new ERC1967Proxy(
            address(impl),
            abi.encodeCall(GameItems.initialize, (admin, "ipfs://t/{id}.json"))
        )));
        items.grantRole(items.MINTER_ROLE(), admin);

        coord = new VRFCoordinatorV2_5Mock();
        subId = coord.createSubscription();
        coord.fundSubscription(subId, 100 ether);

        lootBox = new LootBox(address(coord), bytes32(uint256(1)), subId, IGameItems(address(items)), admin);
        coord.addConsumer(subId, address(lootBox));

        items.grantRole(items.MINTER_ROLE(), address(lootBox));

        LootBox.Reward[] memory r = new LootBox.Reward[](2);
        r[0] = LootBox.Reward({itemId: 10, amount: 1, weight: 7_000});
        r[1] = LootBox.Reward({itemId: 20, amount: 1, weight: 3_000});
        lootBox.setRewards(r);
    }

    function test_open_andFulfill() public {
        vm.prank(player);
        uint256 reqId = lootBox.openLootBox();

        // Force the random word.
        uint256[] memory words = new uint256[](1);
        words[0] = 12345; // pick = 12345 % 10000 = 2345 → first reward
        coord.fulfillRandomWordsWithOverride(reqId, address(lootBox), words);

        assertEq(items.balanceOf(player, 10), 1);
    }

    function test_open_revertsWhenPaused() public {
        lootBox.pause();
        vm.prank(player);
        vm.expectRevert();
        lootBox.openLootBox();
    }

    function test_open_revertsWhenNoRewards() public {
        LootBox.Reward[] memory r = new LootBox.Reward[](0);
        lootBox.setRewards(r);
        vm.prank(player);
        vm.expectRevert(LootBox.NoRewards.selector);
        lootBox.openLootBox();
    }

    function test_setKeyItem_burnsOnOpen() public {
        items.mint(player, 99, 5, "");
        lootBox.setKeyItem(99, 1);

        vm.startPrank(player);
        items.setApprovalForAll(address(lootBox), true);
        uint256 reqId = lootBox.openLootBox();
        vm.stopPrank();

        uint256[] memory words = new uint256[](1);
        words[0] = 1;
        coord.fulfillRandomWordsWithOverride(reqId, address(lootBox), words);

        assertEq(items.balanceOf(player, 99), 4);
    }

    function test_open_revertsWithoutKey() public {
        lootBox.setKeyItem(77, 1);
        vm.prank(player);
        vm.expectRevert(LootBox.NoKey.selector);
        lootBox.openLootBox();
    }

    function test_setRewards_revertsForNonAdmin() public {
        LootBox.Reward[] memory r = new LootBox.Reward[](1);
        r[0] = LootBox.Reward({itemId: 10, amount: 1, weight: 1});
        vm.prank(address(0xBEEF));
        vm.expectRevert();
        lootBox.setRewards(r);
    }

    function test_secondReward_pickedAtHighWord() public {
        vm.prank(player);
        uint256 reqId = lootBox.openLootBox();
        uint256[] memory words = new uint256[](1);
        words[0] = 9_999; // 9999 % 10000 = 9999 → second reward
        coord.fulfillRandomWordsWithOverride(reqId, address(lootBox), words);
        assertEq(items.balanceOf(player, 20), 1);
    }
}
