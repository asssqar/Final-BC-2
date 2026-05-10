"use client";
import {Header} from "@/components/Header";
import {NetworkGuard} from "@/components/NetworkGuard";
import {useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt} from "wagmi";
import {CONTRACTS, isUnconfigured} from "@/config/contracts";
import {ammAbi, erc20Abi} from "@/config/abis";
import {useMemo, useState} from "react";
import {formatUnits, parseUnits, type Address} from "viem";
import {readableTxError} from "@/lib/errors";

export default function SwapPage() {
    const {address, isConnected} = useAccount();
    const [amount, setAmount] = useState("1");
    const [zeroForOne, setZeroForOne] = useState(true);
    const [error, setError] = useState<string | null>(null);

    const {data: token0} = useReadContract({
        address: CONTRACTS.amm, abi: ammAbi, functionName: "token0",
        query: {enabled: !isUnconfigured}});
    const {data: token1} = useReadContract({
        address: CONTRACTS.amm, abi: ammAbi, functionName: "token1",
        query: {enabled: !isUnconfigured}});
    const {data: reserves} = useReadContract({
        address: CONTRACTS.amm, abi: ammAbi, functionName: "getReserves",
        query: {enabled: !isUnconfigured}});

    const tokenIn = (zeroForOne ? token0 : token1) as Address | undefined;
    const r = (reserves as readonly [bigint, bigint, number] | undefined) ?? null;

    const expectedOut = useMemo(() => {
        if (!r || !amount) return 0n;
        try {
            const ai = parseUnits(amount, 18);
            const reserveIn = zeroForOne ? r[0] : r[1];
            const reserveOut = zeroForOne ? r[1] : r[0];
            const amtInFee = ai * 997n;
            return (amtInFee * reserveOut) / (reserveIn * 1000n + amtInFee);
        } catch {
            return 0n;
        }
    }, [r, amount, zeroForOne]);

    const {writeContractAsync, isPending} = useWriteContract();
    const [txHash, setTxHash] = useState<`0x${string}` | null>(null);
    const {isLoading: txLoading, isSuccess} = useWaitForTransactionReceipt({hash: txHash ?? undefined});

    async function onSwap() {
        if (!address || !tokenIn) return;
        setError(null);
        try {
            const amt = parseUnits(amount, 18);
            // Approve, then swap. (We always approve max for UX simplicity.)
            await writeContractAsync({
                address: tokenIn, abi: erc20Abi, functionName: "approve",
                args: [CONTRACTS.amm, amt]
            });
            const minOut = (expectedOut * 99n) / 100n; // 1% slippage
            const hash = await writeContractAsync({
                address: CONTRACTS.amm, abi: ammAbi, functionName: "swap",
                args: [tokenIn, amt, minOut, address]
            });
            setTxHash(hash);
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
                        <h1 className="text-2xl font-semibold mb-4">Resource AMM</h1>
                        {r && (
                            <div className="text-sm text-aether-700 mb-4">
                                Reserves: {formatUnits(r[0], 18)} (token0) ·{" "}
                                {formatUnits(r[1], 18)} (token1)
                            </div>
                        )}

                        <div className="flex items-center gap-4 mb-4">
                            <label className="text-sm font-medium">Direction</label>
                            <button
                                className="btn-secondary"
                                onClick={() => setZeroForOne((z) => !z)}
                            >
                                {zeroForOne ? "token0 → token1" : "token1 → token0"}
                            </button>
                        </div>

                        <label className="block text-sm font-medium mb-1">Amount in</label>
                        <input
                            value={amount}
                            onChange={(e) => setAmount(e.target.value)}
                            className="w-full rounded-xl border border-aether-100 px-3 py-2 mb-4"
                        />

                        <div className="text-sm text-aether-700 mb-4">
                            Expected out: <span className="font-mono">{formatUnits(expectedOut, 18)}</span>{" "}
                            (1% slippage applied)
                        </div>

                        <button
                            className="btn"
                            disabled={!isConnected || isPending || txLoading || isUnconfigured}
                            onClick={onSwap}
                        >
                            {isPending || txLoading ? "Submitting…" : "Swap"}
                        </button>

                        {error && (
                            <div className="mt-4 rounded-lg bg-red-50 border border-red-200 p-3 text-sm text-red-800">
                                {error}
                            </div>
                        )}
                        {isSuccess && (
                            <div className="mt-4 rounded-lg bg-green-50 border border-green-200 p-3 text-sm text-green-800">
                                Swap confirmed.
                            </div>
                        )}
                    </div>
                </NetworkGuard>
            </main>
        </>
    );
}
