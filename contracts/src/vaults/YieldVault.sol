// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title YieldVault
/// @notice ERC-4626 vault that stakes the governance token (AETH) for protocol-fee yield.
/// @dev OZ's ERC-4626 already passes the standard rounding invariants
///      (deposit rounds shares DOWN, withdraw rounds assets UP). We additionally:
///        - Pause via AccessControl + Pausable.
///        - Donation-attack mitigation: we override `_decimalsOffset()` to return 6, so the share
///          token has 6 more decimals than the asset (OZ recommendation).
///        - Withdrawal queue is direct (no lockup) — protocol fees flow in via
///          `notifyRewards` callable by the AMM/RentalVault (granted REWARD_DEPOSITOR_ROLE).
contract YieldVault is ERC4626, AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant REWARD_DEPOSITOR_ROLE = keccak256("REWARD_DEPOSITOR_ROLE");

    event RewardsNotified(address indexed from, uint256 amount);

    constructor(IERC20 asset_, address admin)
        ERC4626(asset_)
        ERC20("Aetheria Vault Share", "vAETH")
    {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
    }

    function _decimalsOffset() internal pure override returns (uint8) {
        return 6; // 6 extra decimals → mitigates inflation/donation attacks at first deposit
    }

    /// @notice Direct asset transfer-in path for protocol fees. Caller must have already
    ///         transferred `amount` of the underlying asset to the vault, OR have approved it.
    ///         We pull the funds and emit, with no share minting (yield accrues to existing LPs).
    function notifyRewards(address from, uint256 amount)
        external
        nonReentrant
        whenNotPaused
        onlyRole(REWARD_DEPOSITOR_ROLE)
    {
        IERC20(asset()).safeTransferFrom(from, address(this), amount);
        emit RewardsNotified(from, amount);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // -----------------------------------------------------------------------
    // Pause-aware overrides
    // -----------------------------------------------------------------------

    function deposit(uint256 assets, address receiver)
        public
        override
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        return super.deposit(assets, receiver);
    }

    function mint(uint256 shares, address receiver)
        public
        override
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        return super.mint(shares, receiver);
    }

    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        return super.withdraw(assets, receiver, owner);
    }

    function redeem(uint256 shares, address receiver, address owner)
        public
        override
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        return super.redeem(shares, receiver, owner);
    }
}
