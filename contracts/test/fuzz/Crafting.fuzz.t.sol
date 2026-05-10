// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {GameItems} from "../../src/tokens/GameItems.sol";

contract CraftingFuzzTest is Test {
    GameItems internal items;
    address internal admin = address(this);
    address internal alice = address(0xA1);

    function setUp() public {
        GameItems impl = new GameItems();
        items = GameItems(address(new ERC1967Proxy(
            address(impl),
            abi.encodeCall(GameItems.initialize, (admin, "ipfs://t/{id}.json"))
        )));
        items.grantRole(items.MINTER_ROLE(), admin);

        uint256[] memory ids = new uint256[](2);
        ids[0] = 1; ids[1] = 2;
        uint256[] memory amts = new uint256[](2);
        amts[0] = 2; amts[1] = 1;
        items.setRecipe(1, ids, amts, 1_000, 1, 0);
    }

    function testFuzz_craftBurnsAndMintsCorrectly(uint16 multiplier) public {
        vm.assume(multiplier > 0);
        uint256 wood = uint256(multiplier) * 2;
        uint256 iron = uint256(multiplier) * 1;
        items.mint(alice, 1, wood, "");
        items.mint(alice, 2, iron, "");
        vm.prank(alice);
        items.craft(1, multiplier);
        assertEq(items.balanceOf(alice, 1), 0);
        assertEq(items.balanceOf(alice, 2), 0);
        assertEq(items.balanceOf(alice, 1_000), uint256(multiplier));
    }

    function testFuzz_craft_revertsIfShort(uint16 multiplier, uint16 woodShortage) public {
        vm.assume(multiplier > 0 && woodShortage > 0);
        uint256 wood = uint256(multiplier) * 2;
        if (wood == 0) return;
        if (woodShortage > wood) woodShortage = uint16(wood);
        uint256 iron = uint256(multiplier);
        items.mint(alice, 1, wood - woodShortage, "");
        items.mint(alice, 2, iron, "");
        vm.prank(alice);
        vm.expectRevert();
        items.craft(1, multiplier);
    }
}
