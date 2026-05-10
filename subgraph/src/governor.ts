import {BigInt} from "@graphprotocol/graph-ts";
import {
    ProposalCreated as ProposalCreatedEvent,
    ProposalExecuted as ProposalExecutedEvent,
    ProposalCanceled as ProposalCanceledEvent,
    VoteCast as VoteCastEvent
} from "../generated/GameGovernor/GameGovernor";
import {Proposal} from "../generated/schema";

const ZERO = BigInt.fromI32(0);

export function handleProposalCreated(event: ProposalCreatedEvent): void {
    const id = event.params.proposalId.toString();
    const p = new Proposal(id);
    p.proposer = event.params.proposer;
    p.description = event.params.description;
    p.state = "Pending";
    p.forVotes = ZERO;
    p.againstVotes = ZERO;
    p.abstainVotes = ZERO;
    p.startTime = event.params.voteStart;
    p.endTime = event.params.voteEnd;
    p.createdAt = event.block.timestamp;
    p.save();
}

export function handleProposalExecuted(event: ProposalExecutedEvent): void {
    const p = Proposal.load(event.params.proposalId.toString());
    if (p == null) return;
    p.state = "Executed";
    p.save();
}

export function handleProposalCanceled(event: ProposalCanceledEvent): void {
    const p = Proposal.load(event.params.proposalId.toString());
    if (p == null) return;
    p.state = "Canceled";
    p.save();
}

export function handleVoteCast(event: VoteCastEvent): void {
    const p = Proposal.load(event.params.proposalId.toString());
    if (p == null) return;
    if (event.params.support === 0) {
        p.againstVotes = p.againstVotes.plus(event.params.weight);
    } else if (event.params.support === 1) {
        p.forVotes = p.forVotes.plus(event.params.weight);
    } else {
        p.abstainVotes = p.abstainVotes.plus(event.params.weight);
    }
    p.save();
}
