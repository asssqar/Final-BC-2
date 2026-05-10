"use client";
import {Header} from "@/components/Header";
import {NetworkGuard} from "@/components/NetworkGuard";
import {useAccount, useWriteContract, useWaitForTransactionReceipt} from "wagmi";
import {CONTRACTS, isUnconfigured} from "@/config/contracts";
import {governorAbi} from "@/config/abis";
import {useEffect, useState} from "react";
import {subgraphClient} from "@/lib/subgraph";
import {ACTIVE_PROPOSALS} from "@/lib/queries";
import {readableTxError} from "@/lib/errors";

interface SubProposal {
    id: string;
    description: string;
    state: string;
    forVotes: string;
    againstVotes: string;
    abstainVotes: string;
    startTime: string;
    endTime: string;
}

const STATE_NAMES = [
    "Pending",
    "Active",
    "Canceled",
    "Defeated",
    "Succeeded",
    "Queued",
    "Expired",
    "Executed",
];

export default function GovernancePage() {
    const {address, isConnected} = useAccount();
    const [proposals, setProposals] = useState<SubProposal[]>([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState<string | null>(null);
    const [txHash, setTxHash] = useState<`0x${string}` | null>(null);
    const {writeContractAsync, isPending} = useWriteContract();
    const {isLoading: txLoading} = useWaitForTransactionReceipt({hash: txHash ?? undefined});

    useEffect(() => {
        let mounted = true;
        (async () => {
            try {
                const r = await subgraphClient.query(ACTIVE_PROPOSALS, {}).toPromise();
                if (!mounted) return;
                setProposals((r.data?.proposals ?? []) as SubProposal[]);
            } catch (e) {
                if (mounted) setError(readableTxError(e));
            } finally {
                if (mounted) setLoading(false);
            }
        })();
        return () => {
            mounted = false;
        };
    }, []);

    async function vote(id: string, support: 0 | 1 | 2) {
        if (!address) return;
        setError(null);
        try {
            const h = await writeContractAsync({
                address: CONTRACTS.governor,
                abi: governorAbi,
                functionName: "castVote",
                args: [BigInt(id), support],
            });
            setTxHash(h);
        } catch (e) {
            setError(readableTxError(e));
        }
    }

    return (
        <>
            <Header />
            <main className="max-w-4xl mx-auto px-6 py-10">
                <NetworkGuard>
                    <h1 className="text-2xl font-semibold mb-4">Active Proposals</h1>

                    {loading && <div>Loading from subgraph…</div>}

                    {!loading && proposals.length === 0 && (
                        <div className="text-aether-700">No proposals yet.</div>
                    )}

                    <div className="grid gap-4">
                        {proposals.map((p) => (
                            <div className="card" key={p.id}>
                                <div className="text-xs text-aether-700 font-mono">{p.id.slice(0, 14)}…</div>
                                <h3 className="font-semibold mt-1">{p.description.slice(0, 200)}</h3>
                                <div className="text-sm mt-2 text-aether-700">
                                    State: <b>{p.state}</b> · For: {p.forVotes} · Against:{" "}
                                    {p.againstVotes} · Abstain: {p.abstainVotes}
                                </div>
                                <div className="flex gap-2 mt-3">
                                    <button
                                        className="btn"
                                        disabled={!isConnected || isPending || txLoading || isUnconfigured}
                                        onClick={() => vote(p.id, 1)}
                                    >
                                        Vote FOR
                                    </button>
                                    <button
                                        className="btn-secondary"
                                        disabled={!isConnected || isPending || txLoading || isUnconfigured}
                                        onClick={() => vote(p.id, 0)}
                                    >
                                        Vote AGAINST
                                    </button>
                                    <button
                                        className="btn-secondary"
                                        disabled={!isConnected || isPending || txLoading || isUnconfigured}
                                        onClick={() => vote(p.id, 2)}
                                    >
                                        Abstain
                                    </button>
                                </div>
                            </div>
                        ))}
                    </div>

                    {error && (
                        <div className="mt-4 rounded-lg bg-red-50 border border-red-200 p-3 text-sm text-red-800">
                            {error}
                        </div>
                    )}
                </NetworkGuard>
            </main>
        </>
    );
}
