// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {
    AggregatorV3Interface
} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {IPriceOracle} from "../interfaces/IPriceOracle.sol";

/// @title PriceOracle
/// @notice Adapter wrapping Chainlink AggregatorV3 feeds.
///         - Per-asset feed registration (governance-only).
///         - Per-asset staleness window (default 1 hour).
///         - Reverts on stale, zero, or negative reads.
///         - Normalises the 8-decimal Chainlink answer to 1e18.
/// @dev Required by §3.1: Chainlink price feed integration with staleness check + mock.
contract PriceOracle is IPriceOracle, AccessControl {
    bytes32 public constant FEED_ADMIN_ROLE = keccak256("FEED_ADMIN_ROLE");

    struct FeedConfig {
        AggregatorV3Interface feed;
        uint64 staleness; // seconds
        uint8 decimals; // cached decimals of the feed
        bool registered;
    }

    mapping(address asset => FeedConfig) internal _feeds;

    event FeedSet(address indexed asset, address indexed feed, uint64 staleness);

    error FeedNotSet(address asset);
    error StalePrice(uint256 updatedAt, uint256 staleness);
    error InvalidPrice(int256 answer);
    error ZeroAddress();

    constructor(address admin) {
        if (admin == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(FEED_ADMIN_ROLE, admin);
    }

    function setFeed(address asset, address feed, uint64 staleness)
        external
        onlyRole(FEED_ADMIN_ROLE)
    {
        if (asset == address(0) || feed == address(0)) revert ZeroAddress();
        require(staleness > 0, "PriceOracle: zero staleness");
        AggregatorV3Interface agg = AggregatorV3Interface(feed);
        uint8 d = agg.decimals();
        _feeds[asset] = FeedConfig({feed: agg, staleness: staleness, decimals: d, registered: true});
        emit FeedSet(asset, feed, staleness);
    }

    function getLatestPrice(address asset)
        external
        view
        override
        returns (uint256 priceWad, uint256 updatedAt)
    {
        FeedConfig memory cfg = _feeds[asset];
        if (!cfg.registered) revert FeedNotSet(asset);

        (, int256 answer,, uint256 _updatedAt, uint80 answeredInRound) = cfg.feed.latestRoundData();
        if (answer <= 0) revert InvalidPrice(answer);
        if (answeredInRound == 0) revert InvalidPrice(answer);
        if (block.timestamp - _updatedAt > cfg.staleness) {
            revert StalePrice(_updatedAt, cfg.staleness);
        }

        uint256 raw = uint256(answer);
        if (cfg.decimals < 18) {
            priceWad = raw * 10 ** (18 - cfg.decimals);
        } else if (cfg.decimals > 18) {
            priceWad = raw / 10 ** (cfg.decimals - 18);
        } else {
            priceWad = raw;
        }
        updatedAt = _updatedAt;
    }

    function stalenessWindow(address asset) external view override returns (uint256) {
        return _feeds[asset].staleness;
    }

    function feedOf(address asset) external view returns (FeedConfig memory) {
        return _feeds[asset];
    }
}
