// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IGameItems
/// @notice Minimal interface used by other protocol contracts (LootBox, RentalVault, ItemFactory)
///         to interact with the upgradeable ERC-1155 item registry without coupling to its full
///         implementation.
interface IGameItems {
    /// @notice Resource (fungible) IDs occupy [0, RESOURCE_RANGE_END).
    function RESOURCE_RANGE_END() external view returns (uint256);

    /// @notice Mints a quantity of an item to `to`. Restricted by role on the implementation.
    function mint(address to, uint256 id, uint256 amount, bytes calldata data) external;

    /// @notice Batch mint variant.
    function mintBatch(
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes calldata data
    ) external;

    /// @notice Burns a quantity of an item from `from`. Caller must be approved.
    function burn(address from, uint256 id, uint256 amount) external;

    /// @notice ERC-1155 balanceOf passthrough.
    function balanceOf(address account, uint256 id) external view returns (uint256);

    /// @notice ERC-1155 safeTransferFrom passthrough.
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes calldata data
    ) external;
}
