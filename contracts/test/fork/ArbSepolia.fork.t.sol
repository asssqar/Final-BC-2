// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import {PriceOracle} from "../../src/oracles/PriceOracle.sol";

/// @notice Arbitrum Sepolia fork — verifies our PriceOracle works against the real ETH/USD feed
///         on the L2 testnet we deploy to.
contract ArbSepoliaForkTest is Test {
    address constant ETH_USD_ARB_SEPOLIA = 0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165;

    function setUp() public {
        try vm.envString("ARB_SEPOLIA_RPC") returns (string memory rpc) {
            vm.createSelectFork(rpc);
        } catch {
            vm.skip(true);
        }
    }

    function test_PriceOracle_arbSepolia() public {
        PriceOracle oracle = new PriceOracle(address(this));
        oracle.setFeed(address(0xCAFE), ETH_USD_ARB_SEPOLIA, 24 hours);
        (uint256 price, uint256 ts) = oracle.getLatestPrice(address(0xCAFE));
        assertGt(price, 0);
        assertGt(ts, 0);
    }
}
