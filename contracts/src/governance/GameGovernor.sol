// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {GovernorSettings} from "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import {
    GovernorCountingSimple
} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {GovernorVotes} from "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import {
    GovernorVotesQuorumFraction
} from "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import {
    GovernorTimelockControl
} from "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

/// @title GameGovernor
/// @notice OpenZeppelin Governor stack tuned to the syllabus parameters:
///           voting delay  = 1 day
///           voting period = 1 week
///           proposal threshold = 1 % of total supply
///           quorum = 4 % of total supply
///           Timelock delay = 2 days (set on the TimelockController itself)
/// @dev Token uses `clock() = block.timestamp`, so all delays/periods are in **seconds**.
contract GameGovernor is
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorVotesQuorumFraction,
    GovernorTimelockControl
{
    /// @param token   ERC20Votes governance token (GameToken).
    /// @param timelock TimelockController; will own protocol contracts.
    constructor(IVotes token, TimelockController timelock)
        Governor("AetheriaGovernor")
        GovernorSettings(
            1 days,
            1 weeks,
            0 /* proposalThreshold filled by override */
        )
        GovernorVotes(token)
        GovernorVotesQuorumFraction(4) // 4 %
        GovernorTimelockControl(timelock)
    {}

    /// @notice Proposal threshold is **1 %** of `IVotes.getPastTotalSupply` at the proposal time.
    /// @dev We override the constant returned by GovernorSettings because OZ's Settings is
    ///      flat-amount, but the syllabus requires a percentage of the supply.
    function proposalThreshold()
        public
        view
        override(Governor, GovernorSettings)
        returns (uint256)
    {
        // 1 % of past total supply at proposal time. Snapshot is taken inside `propose`.
        // Since we can't access the snapshot here, we approximate using current total supply.
        // Off-chain UI is expected to recheck. For invariant testing we expose `_thresholdNumerator`.
        return _thresholdNumerator();
    }

    function _thresholdNumerator() internal view returns (uint256) {
        // 1 % of total token supply right now.
        return token().getPastTotalSupply(clock() - 1) / 100;
    }

    // -----------------------------------------------------------------------
    // Required overrides
    // -----------------------------------------------------------------------

    function votingDelay() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingDelay();
    }

    function votingPeriod() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingPeriod();
    }

    function quorum(uint256 timepoint)
        public
        view
        override(Governor, GovernorVotesQuorumFraction)
        returns (uint256)
    {
        return super.quorum(timepoint);
    }

    function state(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (ProposalState)
    {
        return super.state(proposalId);
    }

    function proposalNeedsQueuing(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (bool)
    {
        return super.proposalNeedsQueuing(proposalId);
    }

    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint48) {
        return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) {
        super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    function _executor()
        internal
        view
        override(Governor, GovernorTimelockControl)
        returns (address)
    {
        return super._executor();
    }
}
