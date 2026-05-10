// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/// @title MockAggregator
/// @notice Test-only Chainlink AggregatorV3 mock used by `PriceOracle.t.sol` and the local
///         deployment script when running on chains without a real feed.
contract MockAggregator is AggregatorV3Interface {
    int256 private _answer;
    uint256 private _updatedAt;
    uint8 private immutable _decimals;
    uint80 private _roundId;

    constructor(int256 initialAnswer, uint8 decimalsArg) {
        _answer = initialAnswer;
        _decimals = decimalsArg;
        _updatedAt = block.timestamp;
        _roundId = 1;
    }

    function setAnswer(int256 answer) external {
        _answer = answer;
        _updatedAt = block.timestamp;
        ++_roundId;
    }

    function setUpdatedAt(uint256 ts) external {
        _updatedAt = ts;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function description() external pure override returns (string memory) {
        return "MockAggregator";
    }

    function version() external pure override returns (uint256) {
        return 4;
    }

    function getRoundData(uint80)
        external
        view
        override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (_roundId, _answer, _updatedAt, _updatedAt, _roundId);
    }

    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (_roundId, _answer, _updatedAt, _updatedAt, _roundId);
    }
}
