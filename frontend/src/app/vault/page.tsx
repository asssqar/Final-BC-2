"use client";
import {Header} from "@/components/Header";
import {NetworkGuard} from "@/components/NetworkGuard";
import {useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt} from "wagmi";
import {CONTRACTS, isUnconfigured} from "@/config/contracts";
import {erc20Abi, vaultAbi} from "@/config/abis";
import {useState} from "react";
import {formatUnits, parseUnits} from "viem";
import {readableTxError} from "@/lib/errors";

export default function VaultPage() {
    const {address, isConnected} = useAccount();
    const [amount, setAmount] = useState("100");
    const [error, setError] = useState<string | null>(null);
    const [txHash, setTxHash] = useState<`0x${string}` | null>(null);

    const {data: shares} = useReadContract({
        address: CONTRACTS.yieldVault, abi: vaultAbi, functionName: "balanceOf",
        args: address ? [address] : undefined,
        query: {enabled: isConnected && !isUnconfigured}
    });
    const {data: totalAssets} = useReadContract({
        address: CONTRACTS.yieldVault, abi: vaultAbi, functionName: "totalAssets",
        query: {enabled: !isUnconfigured}
    });
    const {data: claimable} = useReadContract({
        address: CONTRACTS.yieldVault, abi: vaultAbi, functionName: "convertToAssets",
        args: shares ? [shares as bigint] : undefined,
        query: {enabled: !!shares && !isUnconfigured}
    });

    const {writeContractAsync, isPending} = useWriteContract();
    const {isLoading: txLoading, isSuccess} = useWaitForTransactionReceipt({hash: txHash ?? undefined});

    async function onDeposit() {
        if (!address) return;
        setError(null);
        try {
            const amt = parseUnits(amount, 18);
            await writeContractAsync({
                address: CONTRACTS.gameToken, abi: erc20Abi, functionName: "approve",
                args: [CONTRACTS.yieldVault, amt]
            });
            const h = await writeContractAsync({
                address: CONTRACTS.yieldVault, abi: vaultAbi, functionName: "deposit",
                args: [amt, address]
            });
            setTxHash(h);
        } catch (e) {
            setError(readableTxError(e));
        }
    }

    async function onWithdrawAll() {
        if (!address || !shares) return;
        setError(null);
        try {
            const h = await writeContractAsync({
                address: CONTRACTS.yieldVault, abi: vaultAbi, functionName: "redeem",
                args: [shares as bigint, address, address]
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
                    <div className="card">
                        <h1 className="text-2xl font-semibold mb-2">Yield Vault (ERC-4626)</h1>
                        <p className="text-aether-700 text-sm mb-4">
                            Stake AETH to receive vAETH and a share of protocol fees.
                        </p>

                        <div className="grid grid-cols-2 gap-4 mb-4 text-sm">
                            <div>
                                <div className="text-aether-700">TVL (assets)</div>
                                <div className="font-mono">
                                    {totalAssets != null
                                        ? formatUnits(totalAssets as bigint, 18)
                                        : "—"}
                                </div>
                            </div>
                            <div>
                                <div className="text-aether-700">Your claim (AETH)</div>
                                <div className="font-mono">
                                    {claimable != null
                                        ? formatUnits(claimable as bigint, 18)
                                        : "—"}
                                </div>
                            </div>
                        </div>

                        <label className="block text-sm font-medium mb-1">Deposit amount</label>
                        <input
                            value={amount}
                            onChange={(e) => setAmount(e.target.value)}
                            className="w-full rounded-xl border border-aether-100 px-3 py-2 mb-4"
                        />

                        <div className="flex gap-3">
                            <button
                                className="btn"
                                disabled={!isConnected || isPending || txLoading || isUnconfigured}
                                onClick={onDeposit}
                            >
                                Deposit
                            </button>
                            <button
                                className="btn-secondary"
                                disabled={!isConnected || !shares || isUnconfigured}
                                onClick={onWithdrawAll}
                            >
                                Withdraw all
                            </button>
                        </div>

                        {error && (
                            <div className="mt-4 rounded-lg bg-red-50 border border-red-200 p-3 text-sm text-red-800">
                                {error}
                            </div>
                        )}
                        {isSuccess && (
                            <div className="mt-4 rounded-lg bg-green-50 border border-green-200 p-3 text-sm text-green-800">
                                Confirmed.
                            </div>
                        )}
                    </div>
                </NetworkGuard>
            </main>
        </>
    );
}
