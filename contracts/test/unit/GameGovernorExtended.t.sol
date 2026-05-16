// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {GameToken} from "../../src/tokens/GameToken.sol";
import {GameGovernor} from "../../src/governance/GameGovernor.sol";

/// @title GameGovernorExtendedTest
/// @notice Covers branches missing from Governance.t.sol to push GameGovernor.sol above 90 % line coverage.
contract GameGovernorExtendedTest is Test {
    GameToken internal token;
    GameGovernor internal governor;
    TimelockController internal timelock;

    address internal admin = address(this);
    address internal voter = address(0xA1);
    address internal minority = address(0xA2);

    uint256 internal constant TOTAL_SUPPLY = 100_000_000e18;

    address[] internal targets;
    uint256[] internal values;
    bytes[] internal cds;
    string internal description = "extended test proposal";
    bytes32 internal descHash;

    function setUp() public {
        token = new GameToken(admin, admin, TOTAL_SUPPLY);

        address[] memory empty = new address[](0);
        timelock = new TimelockController(2 days, empty, empty, admin);
        governor = new GameGovernor(IVotes(address(token)), timelock);

        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0));

        // voter gets 95 % of supply — well above 1 % proposal threshold
        token.transfer(voter, (TOTAL_SUPPLY * 95) / 100);
        // minority gets 0.001 % — below threshold
        token.transfer(minority, TOTAL_SUPPLY / 100_000);
        // admin keeps 4.999 % remainder

        vm.prank(voter);
        token.delegate(voter);
        vm.prank(minority);
        token.delegate(minority);
        // admin self-delegates too (used in fuzz test)
        token.delegate(admin);

        vm.warp(block.timestamp + 1);

        targets = new address[](1);
        targets[0] = address(token);
        values = new uint256[](1);
        cds = new bytes[](1);
        cds[0] = abi.encodeCall(IERC20.transfer, (address(0xdead), 0));
        descHash = keccak256(bytes(description));
    }

    // -----------------------------------------------------------------------
    // View helpers
    // -----------------------------------------------------------------------

    function test_votingDelay_is1Day() public view {
        assertEq(governor.votingDelay(), 1 days);
    }

    function test_votingPeriod_is1Week() public view {
        assertEq(governor.votingPeriod(), 1 weeks);
    }

    function test_quorumNumerator_is4() public view {
        assertEq(governor.quorumNumerator(), 4);
    }

    function test_quorum_currentBlock() public view {
        uint256 q = governor.quorum(block.timestamp - 1);
        assertGt(q, 0);
    }

    function test_countingMode() public view {
        assertEq(governor.COUNTING_MODE(), "support=bravo&quorum=for,abstain");
    }

    function test_proposalThreshold_positive() public view {
        uint256 threshold = governor.proposalThreshold();
        assertGt(threshold, 0);
    }

    // -----------------------------------------------------------------------
    // State: Pending
    // -----------------------------------------------------------------------

    function test_state_pending() public {
        vm.prank(voter);
        uint256 id = governor.propose(targets, values, cds, description);
        assertEq(uint8(governor.state(id)), uint8(IGovernor.ProposalState.Pending));
    }

    // -----------------------------------------------------------------------
    // State: Active
    // -----------------------------------------------------------------------

    function test_state_active() public {
        vm.prank(voter);
        uint256 id = governor.propose(targets, values, cds, description);
        vm.warp(block.timestamp + governor.votingDelay() + 1);
        assertEq(uint8(governor.state(id)), uint8(IGovernor.ProposalState.Active));
    }

    // -----------------------------------------------------------------------
    // Proposal defeated — no votes cast
    // -----------------------------------------------------------------------

    function test_proposal_defeated_noVotes() public {
        vm.prank(voter);
        uint256 id = governor.propose(targets, values, cds, description);
        vm.warp(block.timestamp + governor.votingDelay() + governor.votingPeriod() + 1);
        assertEq(uint8(governor.state(id)), uint8(IGovernor.ProposalState.Defeated));
    }

    // -----------------------------------------------------------------------
    // Proposal defeated — against wins
    // -----------------------------------------------------------------------

    function test_proposal_defeated_againstWins() public {
        vm.prank(voter);
        uint256 id = governor.propose(targets, values, cds, description);
        vm.warp(block.timestamp + governor.votingDelay() + 1);

        vm.prank(voter);
        governor.castVote(id, 0); // Against

        vm.warp(block.timestamp + governor.votingPeriod() + 1);
        assertEq(uint8(governor.state(id)), uint8(IGovernor.ProposalState.Defeated));
    }

    // -----------------------------------------------------------------------
    // Abstain vote counts for quorum but not for/against
    // -----------------------------------------------------------------------

    function test_castVote_abstain_countsForQuorum() public {
        vm.prank(voter);
        uint256 id = governor.propose(targets, values, cds, description);
        vm.warp(block.timestamp + governor.votingDelay() + 1);

        vm.prank(voter);
        governor.castVote(id, 2); // Abstain

        vm.warp(block.timestamp + governor.votingPeriod() + 1);
        // Abstain reaches quorum but no FOR votes → Defeated
        assertEq(uint8(governor.state(id)), uint8(IGovernor.ProposalState.Defeated));
    }

    // -----------------------------------------------------------------------
    // Proposal cancelled by proposer
    // -----------------------------------------------------------------------

    function test_cancel_byProposer() public {
        vm.prank(voter);
        uint256 id = governor.propose(targets, values, cds, description);
        vm.prank(voter);
        governor.cancel(targets, values, cds, descHash);
        assertEq(uint8(governor.state(id)), uint8(IGovernor.ProposalState.Canceled));
    }

    // -----------------------------------------------------------------------
    // proposalNeedsQueuing() returns true (timelock governor)
    // -----------------------------------------------------------------------

    function test_proposalNeedsQueuing_returnsTrue() public {
        vm.prank(voter);
        uint256 id = governor.propose(targets, values, cds, description);
        assertTrue(governor.proposalNeedsQueuing(id));
    }

    // -----------------------------------------------------------------------
    // proposalSnapshot / proposalDeadline
    // -----------------------------------------------------------------------

    function test_proposalSnapshot_and_deadline() public {
        uint256 before = block.timestamp;
        vm.prank(voter);
        uint256 id = governor.propose(targets, values, cds, description);
        uint256 snap = governor.proposalSnapshot(id);
        uint256 deadline = governor.proposalDeadline(id);
        assertGe(snap, before);
        assertGt(deadline, snap);
        assertEq(deadline - snap, governor.votingPeriod());
    }

    // -----------------------------------------------------------------------
    // hasVoted() before and after
    // -----------------------------------------------------------------------

    function test_hasVoted_before_and_after() public {
        vm.prank(voter);
        uint256 id = governor.propose(targets, values, cds, description);
        vm.warp(block.timestamp + governor.votingDelay() + 1);

        assertFalse(governor.hasVoted(id, voter));
        vm.prank(voter);
        governor.castVote(id, 1);
        assertTrue(governor.hasVoted(id, voter));
    }

    // -----------------------------------------------------------------------
    // getVotes matches delegated balance
    // -----------------------------------------------------------------------

    function test_getVotes_matchesDelegatedBalance() public view {
        uint256 votes = governor.getVotes(voter, block.timestamp - 1);
        assertEq(votes, token.getPastVotes(voter, block.timestamp - 1));
    }

    // -----------------------------------------------------------------------
    // Double-vote reverts
    // -----------------------------------------------------------------------

    function test_doubleVote_reverts() public {
        vm.prank(voter);
        uint256 id = governor.propose(targets, values, cds, description);
        vm.warp(block.timestamp + governor.votingDelay() + 1);

        vm.prank(voter);
        governor.castVote(id, 1);
        vm.prank(voter);
        vm.expectRevert();
        governor.castVote(id, 1);
    }

    // -----------------------------------------------------------------------
    // Full lifecycle: propose → vote → queue → execute
    // -----------------------------------------------------------------------

    function test_fullLifecycle_queueAndExecute() public {
        vm.prank(voter);
        uint256 id = governor.propose(targets, values, cds, description);

        vm.warp(block.timestamp + governor.votingDelay() + 1);
        vm.prank(voter);
        governor.castVote(id, 1); // FOR

        vm.warp(block.timestamp + governor.votingPeriod() + 1);
        assertEq(uint8(governor.state(id)), uint8(IGovernor.ProposalState.Succeeded));

        governor.queue(targets, values, cds, descHash);
        assertEq(uint8(governor.state(id)), uint8(IGovernor.ProposalState.Queued));

        vm.warp(block.timestamp + 2 days + 1);
        governor.execute(targets, values, cds, descHash);
        assertEq(uint8(governor.state(id)), uint8(IGovernor.ProposalState.Executed));
    }

    // -----------------------------------------------------------------------
    // _executor() is the timelock (verified by role)
    // -----------------------------------------------------------------------

    function test_executor_isTimelock() public view {
        assertTrue(timelock.hasRole(timelock.PROPOSER_ROLE(), address(governor)));
    }

    // -----------------------------------------------------------------------
    // Fuzz: voting weight equals delegated balance at snapshot
    //
    // Strategy: give fuzzVoter tokens from ADMIN's remainder (not from voter)
    // so voter stays above threshold and can still propose.
    // Admin has ~4.999% = ~4,999,000e18 tokens after setUp.
    // -----------------------------------------------------------------------

    function testFuzz_voteWeight_equalsBalance(uint96 amount) public {
        // Admin remainder after setUp: TOTAL_SUPPLY - 95% - 0.001% ≈ 4,999,000e18
        // Bound to 1e18..1,000,000e18 so admin still has tokens left for proposal threshold
        amount = uint96(bound(uint256(amount), 1e18, 1_000_000e18));
        address fuzzVoter = address(0xF1);

        // Transfer from admin to fuzzVoter
        token.transfer(fuzzVoter, amount);
        vm.prank(fuzzVoter);
        token.delegate(fuzzVoter);
        vm.warp(block.timestamp + 1);

        // voter (95% holder) proposes
        vm.prank(voter);
        uint256 id = governor.propose(targets, values, cds, description);
        vm.warp(block.timestamp + governor.votingDelay() + 1);

        vm.prank(fuzzVoter);
        governor.castVote(id, 1);

        uint256 snap = governor.proposalSnapshot(id);
        uint256 expectedWeight = token.getPastVotes(fuzzVoter, snap);
        (,, uint256 forVotes) = governor.proposalVotes(id);
        assertEq(forVotes, expectedWeight);
    }
}
