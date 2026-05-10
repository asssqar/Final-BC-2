"use client";
import {useAccount, useReadContract} from "wagmi";
import {Header} from "@/components/Header";
import {NetworkGuard} from "@/components/NetworkGuard";
import {CONTRACTS, isUnconfigured} from "@/config/contracts";
import {gameTokenAbi} from "@/config/abis";
import {formatUnits} from "viem";

function StatLine({label, value}: {label: string; value: string}) {
    return (
        <div className="flex justify-between text-sm py-1">
            <span className="text-aether-700">{label}</span>
            <span className="font-mono">{value}</span>
        </div>
    );
}

export default function Home() {
    const {address, isConnected} = useAccount();

    const {data: balance} = useReadContract({
        address: CONTRACTS.gameToken,
        abi: gameTokenAbi,
        functionName: "balanceOf",
        args: address ? [address] : undefined,
        query: {enabled: isConnected && !isUnconfigured},
    });
    const {data: votes} = useReadContract({
        address: CONTRACTS.gameToken,
        abi: gameTokenAbi,
        functionName: "getVotes",
        args: address ? [address] : undefined,
        query: {enabled: isConnected && !isUnconfigured},
    });
    const {data: delegateAddr} = useReadContract({
        address: CONTRACTS.gameToken,
        abi: gameTokenAbi,
        functionName: "delegates",
        args: address ? [address] : undefined,
        query: {enabled: isConnected && !isUnconfigured},
    });

    return (
        <>
            <Header />
            <main className="max-w-6xl mx-auto px-6 py-10">
                <NetworkGuard>
                    <section className="grid md:grid-cols-2 gap-8">
                        <div className="card">
                            <h1 className="text-3xl font-semibold mb-2">Welcome to Aetheria</h1>
                            <p className="text-aether-700">
                                Craft, trade, rent, and govern an on-chain game economy. Connect
                                your wallet to begin.
                            </p>
                            {isUnconfigured && (
                                <div className="mt-4 rounded-lg bg-amber-50 border border-amber-200 p-3 text-sm text-amber-800">
                                    Contracts not yet deployed. Run{" "}
                                    <code>forge script script/Deploy.s.sol</code> in the{" "}
                                    <code>contracts/</code> directory and refresh.
                                </div>
                            )}
                        </div>

                        <div className="card">
                            <h2 className="text-lg font-semibold mb-3">Your account</h2>
                            <StatLine
                                label="AETH balance"
                                value={
                                    balance != null
                                        ? formatUnits(balance as bigint, 18)
                                        : isConnected
                                            ? "—"
                                            : "Connect wallet"
                                }
                            />
                            <StatLine
                                label="Voting power"
                                value={votes != null ? formatUnits(votes as bigint, 18) : "—"}
                            />
                            <StatLine
                                label="Delegate"
                                value={(delegateAddr as string) ?? "—"}
                            />
                        </div>
                    </section>
                </NetworkGuard>
            </main>
        </>
    );
}
