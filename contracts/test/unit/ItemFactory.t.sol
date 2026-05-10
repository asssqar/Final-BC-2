// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ItemFactory} from "../../src/factory/ItemFactory.sol";
import {GameItems} from "../../src/tokens/GameItems.sol";

contract ItemFactoryUnitTest is Test {
    ItemFactory internal factory;
    GameItems internal impl;
    address internal admin = address(this);

    function setUp() public {
        factory = new ItemFactory(admin);
        impl = new GameItems();
    }

    function test_create_deploysProxy() public {
        bytes memory data = abi.encodeCall(GameItems.initialize, (admin, "ipfs://x"));
        address proxy = factory.deployERC1967Proxy(address(impl), data);
        assertEq(GameItems(proxy).version(), "1.0.0");
    }

    function test_create2_isDeterministic() public {
        bytes memory data = abi.encodeCall(GameItems.initialize, (admin, "ipfs://x"));
        bytes32 salt = keccak256("season1");
        address predicted = factory.predictProxyAddress(address(impl), data, salt);
        address actual = factory.deployERC1967ProxyDeterministic(address(impl), data, salt);
        assertEq(predicted, actual);
    }

    function test_create2_revertsOnDuplicateSalt() public {
        bytes memory data = abi.encodeCall(GameItems.initialize, (admin, "ipfs://x"));
        bytes32 salt = keccak256("dup");
        factory.deployERC1967ProxyDeterministic(address(impl), data, salt);
        vm.expectRevert();
        factory.deployERC1967ProxyDeterministic(address(impl), data, salt);
    }

    function test_unauthorized_reverts() public {
        bytes memory data = abi.encodeCall(GameItems.initialize, (admin, "ipfs://x"));
        vm.prank(address(0xDEAD));
        vm.expectRevert();
        factory.deployERC1967Proxy(address(impl), data);
    }
}
