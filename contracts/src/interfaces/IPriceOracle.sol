// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IPriceOracle
/// @notice Adapter abstraction over Chainlink AggregatorV3Interface so that the rest of the
///         protocol depends on a stable, narrow surface (Pattern: Oracle Adapter / Interface
///         Abstraction).
interface IPriceOracle {
    /// @notice Returns the latest price scaled to 1e18 along with the source feed timestamp.
    /// @dev Reverts if the feed is stale (older than the configured staleness window) or if the
    ///      reported price is non-positive.
    function getLatestPrice(address asset)
        external
        view
        returns (uint256 priceWad, uint256 updatedAt);

    /// @notice Returns the configured staleness window for `asset`, in seconds.
    function stalenessWindow(address asset) external view returns (uint256);
}
