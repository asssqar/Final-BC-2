// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

import {GameToken} from "../../src/tokens/GameToken.sol";
import {GameGovernor} from "../../src/governance/GameGovernor.sol";

contract GovernanceUnitTest is Test {
    GameToken internal token;
    GameGovernor internal governor;
    TimelockController internal timelock;
    address internal admin = address(this);
    address internal voter = address(0xA1);

    function setUp() public {
        token = new GameToken(admin, admin, 100_000_000e18); // full supply
        address[] memory empty = new address[](0);
        timelock = new TimelockController(2 days, empty, empty, admin);
        governor = new GameGovernor(IVotes(address(token)), timelock);

        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0));

        // Move all tokens to voter and self-delegate.
        token.transfer(voter, token.totalSupply());
        vm.prank(voter);
        token.delegate(voter);
        vm.warp(block.timestamp + 1);
    }

    function test_settings_matchSyllabus() public view {
        assertEq(governor.votingDelay(), 1 days);
        assertEq(governor.votingPeriod(), 1 weeks);
        assertEq(governor.quorumNumerator(), 4);
    }

    function test_proposalLifecycle() public {
        // Build a no-op proposal (transfer 0 to address(0))
        address[] memory targets = new address[](1);
        targets[0] = address(token);
        uint256[] memory values = new uint256[](1);
        bytes[] memory cds = new bytes[](1);
        cds[0] = abi.encodeCall(GameToken.transfer, (address(0xdead), 1));
        string memory description = "test proposal";

        // Voter proposes.
        vm.prank(voter);
        uint256 id = governor.propose(targets, values, cds, description);

        // Skip past voting delay
        vm.warp(block.timestamp + governor.votingDelay() + 1);
        assertEq(uint8(governor.state(id)), uint8(IGovernor.ProposalState.Active));

        vm.prank(voter);
        governor.castVote(id, 1); // FOR

        // Skip past voting period
        vm.warp(block.timestamp + governor.votingPeriod() + 1);
        assertEq(uint8(governor.state(id)), uint8(IGovernor.ProposalState.Succeeded));

        // Queue
        bytes32 descHash = keccak256(bytes(description));
        governor.queue(targets, values, cds, descHash);
        assertEq(uint8(governor.state(id)), uint8(IGovernor.ProposalState.Queued));

        // Wait timelock delay
        vm.warp(block.timestamp + 2 days + 1);

        // Need timelock to actually be able to send token.transfer — give it tokens first
        token.transfer(address(timelock), 1);
        governor.execute(targets, values, cds, descHash);
        assertEq(uint8(governor.state(id)), uint8(IGovernor.ProposalState.Executed));
    }

    function test_proposalThreshold_notMet_reverts() public {
        address poor = address(0xB0B);
        token.transfer(poor, 100);
        vm.prank(poor);
        token.delegate(poor);
        vm.warp(block.timestamp + 1);

        address[] memory targets = new address[](1);
        targets[0] = address(token);
        uint256[] memory values = new uint256[](1);
        bytes[] memory cds = new bytes[](1);
        cds[0] = abi.encodeCall(GameToken.transfer, (address(0xdead), 1));

        vm.prank(poor);
        vm.expectRevert();
        governor.propose(targets, values, cds, "fail");
    }
}
