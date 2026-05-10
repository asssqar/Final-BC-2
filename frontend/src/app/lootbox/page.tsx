"use client";
import {Header} from "@/components/Header";
import {NetworkGuard} from "@/components/NetworkGuard";
import {useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt} from "wagmi";
import {CONTRACTS, isUnconfigured} from "@/config/contracts";
import {lootBoxAbi} from "@/config/abis";
import {useState} from "react";
import {readableTxError} from "@/lib/errors";

export default function LootBoxPage() {
    const {isConnected} = useAccount();
    const [error, setError] = useState<string | null>(null);
    const [txHash, setTxHash] = useState<`0x${string}` | null>(null);
    const {writeContractAsync, isPending} = useWriteContract();
    const {isLoading: txLoading, isSuccess} = useWaitForTransactionReceipt({hash: txHash ?? undefined});

    const {data: count} = useReadContract({
        address: CONTRACTS.lootBox,
        abi: lootBoxAbi,
        functionName: "rewardCount",
        query: {enabled: !isUnconfigured},
    });

    async function open() {
        setError(null);
        try {
            const h = await writeContractAsync({
                address: CONTRACTS.lootBox,
                abi: lootBoxAbi,
                functionName: "openLootBox",
            });
            setTxHash(h);
        } catch (e) {
            setError(readableTxError(e));
        }
    }

    return (
        <>
            <Header />
            <main className="max-w-3xl mx-auto px-6 py-10">
                <NetworkGuard>
                    <div className="card text-center">
                        <h1 className="text-2xl font-semibold mb-2">Loot Box (Chainlink VRF)</h1>
                        <p className="text-aether-700 text-sm mb-4">
                            Reward table size:{" "}
                            <span className="font-mono">{count?.toString() ?? "—"}</span> ·
                            randomness via Chainlink VRF v2.5.
                        </p>
                        <button
                            className="btn text-lg"
                            disabled={!isConnected || isPending || txLoading || isUnconfigured}
                            onClick={open}
                        >
                            {isPending || txLoading ? "Requesting randomness…" : "Open Loot Box"}
                        </button>

                        <p className="text-xs text-aether-700 mt-4">
                            VRF fulfilment can take 1–2 minutes. Track the result on the
                            Leaderboard tab once it's settled.
                        </p>

                        {error && (
                            <div className="mt-4 rounded-lg bg-red-50 border border-red-200 p-3 text-sm text-red-800">
                                {error}
                            </div>
                        )}
                        {isSuccess && (
                            <div className="mt-4 rounded-lg bg-green-50 border border-green-200 p-3 text-sm text-green-800">
                                VRF request sent. Awaiting fulfillment.
                            </div>
                        )}
                    </div>
                </NetworkGuard>
            </main>
        </>
    );
}
