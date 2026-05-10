// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {PriceOracle} from "../../src/oracles/PriceOracle.sol";
import {MockAggregator} from "../../src/oracles/MockAggregator.sol";

contract PriceOracleUnitTest is Test {
    PriceOracle internal oracle;
    MockAggregator internal feed;
    address internal asset = address(0xAB);
    address internal admin = address(this);

    function setUp() public {
        feed = new MockAggregator(2_000e8, 8);
        oracle = new PriceOracle(admin);
        oracle.setFeed(asset, address(feed), 1 hours);
    }

    function test_getLatestPrice_scalesTo1e18() public view {
        (uint256 p,) = oracle.getLatestPrice(asset);
        assertEq(p, 2_000e18);
    }

    function test_getLatestPrice_revertsOnStale() public {
        vm.warp(block.timestamp + 2 hours);
        vm.expectRevert();
        oracle.getLatestPrice(asset);
    }

    function test_getLatestPrice_revertsOnNegative() public {
        feed.setAnswer(-1);
        vm.expectRevert(abi.encodeWithSelector(PriceOracle.InvalidPrice.selector, int256(-1)));
        oracle.getLatestPrice(asset);
    }

    function test_getLatestPrice_revertsOnZero() public {
        feed.setAnswer(0);
        vm.expectRevert();
        oracle.getLatestPrice(asset);
    }

    function test_setFeed_revertsOnZeroAddr() public {
        vm.expectRevert(PriceOracle.ZeroAddress.selector);
        oracle.setFeed(address(0), address(feed), 1 hours);
    }

    function test_unregisteredFeed_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(PriceOracle.FeedNotSet.selector, address(0xCD)));
        oracle.getLatestPrice(address(0xCD));
    }

    function test_setFeed_byNonAdmin_reverts() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert();
        oracle.setFeed(asset, address(feed), 1 hours);
    }
}
