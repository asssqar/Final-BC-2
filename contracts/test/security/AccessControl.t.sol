// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {GameItems} from "../../src/tokens/GameItems.sol";
import {GameToken} from "../../src/tokens/GameToken.sol";
import {PriceOracle} from "../../src/oracles/PriceOracle.sol";
import {MockAggregator} from "../../src/oracles/MockAggregator.sol";

/// @notice Case study #2: access-control gap — a privileged setter that lacked role gating.
/// @dev We document the pattern and prove that every privileged path in the production contracts
///      reverts when called by an unauthorized caller. A historical "vulnerable" prototype of
///      `PriceOracle.setFeed` (without `onlyRole`) would have allowed anyone to inject a malicious
///      oracle. This test asserts the fixed version reverts.
contract AccessControlTest is Test {
    GameItems internal items;
    GameToken internal token;
    PriceOracle internal oracle;
    MockAggregator internal feed;

    address internal admin = address(this);
    address internal attacker = address(0xBAD);

    function setUp() public {
        token = new GameToken(admin, admin, 1e24);
        feed = new MockAggregator(2_000e8, 8);
        oracle = new PriceOracle(admin);
        oracle.setFeed(address(token), address(feed), 1 hours);

        GameItems impl = new GameItems();
        items = GameItems(address(new ERC1967Proxy(
            address(impl),
            abi.encodeCall(GameItems.initialize, (admin, "ipfs://t/{id}.json"))
        )));
    }

    function test_setFeed_isProtected() public {
        vm.prank(attacker);
        vm.expectRevert();
        oracle.setFeed(address(token), address(feed), 1 hours);
    }

    function test_mint_isProtected() public {
        vm.prank(attacker);
        vm.expectRevert();
        items.mint(attacker, 1, 1, "");
    }

    function test_setRecipe_isProtected() public {
        uint256[] memory ids = new uint256[](1);
        uint256[] memory amts = new uint256[](1);
        ids[0] = 1; amts[0] = 1;
        vm.prank(attacker);
        vm.expectRevert();
        items.setRecipe(1, ids, amts, 1_000, 1, 0);
    }

    function test_pause_isProtected() public {
        vm.prank(attacker);
        vm.expectRevert();
        items.pause();
    }

    function test_upgrade_isProtected() public {
        GameItems newImpl = new GameItems();
        vm.prank(attacker);
        vm.expectRevert();
        items.upgradeToAndCall(address(newImpl), "");
    }

    function test_tokenMint_isProtected() public {
        vm.prank(attacker);
        vm.expectRevert();
        token.mint(attacker, 1);
    }
}
