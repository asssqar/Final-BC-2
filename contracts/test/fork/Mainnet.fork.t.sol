// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    AggregatorV3Interface
} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import {PriceOracle} from "../../src/oracles/PriceOracle.sol";

/// @notice Fork tests that talk to mainnet protocols. Run with:
///         forge test --match-contract MainnetForkTest --fork-url $MAINNET_RPC
contract MainnetForkTest is Test {
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant ETH_USD = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    function setUp() public {
        try vm.envString("MAINNET_RPC") returns (string memory rpc) {
            vm.createSelectFork(rpc);
        } catch {
            vm.skip(true);
        }
    }

    function test_USDC_isERC20() public view {
        IERC20 usdc = IERC20(USDC);
        assertGt(usdc.totalSupply(), 0);
    }

    function test_ChainlinkETHUSD_returnsPositive() public view {
        AggregatorV3Interface feed = AggregatorV3Interface(ETH_USD);
        (, int256 answer,, uint256 updatedAt,) = feed.latestRoundData();
        assertGt(answer, 0);
        assertLt(block.timestamp - updatedAt, 1 hours, "ETH/USD stale");
    }

    function test_PriceOracle_wrapsRealFeed() public {
        PriceOracle oracle = new PriceOracle(address(this));
        oracle.setFeed(USDC, ETH_USD, 2 hours);
        (uint256 price, uint256 ts) = oracle.getLatestPrice(USDC);
        assertGt(price, 1000e18); // ETH way above $1k
        assertGt(ts, 0);
    }
}
