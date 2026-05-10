"use client";
import {useAccount, useChainId, useSwitchChain} from "wagmi";
import {TARGET_CHAIN} from "@/config/wagmi";

export function NetworkGuard({children}: {children: React.ReactNode}) {
    const {isConnected} = useAccount();
    const chainId = useChainId();
    const {switchChain, isPending} = useSwitchChain();

    if (!isConnected) return <>{children}</>;
    if (chainId === TARGET_CHAIN.id) return <>{children}</>;

    return (
        <div className="card border-amber-300 bg-amber-50 text-amber-800 max-w-2xl mx-auto mt-10">
            <h2 className="text-lg font-semibold">Wrong network</h2>
            <p className="mt-2 text-sm">
                Aetheria runs on <b>{TARGET_CHAIN.name}</b> (chain id {TARGET_CHAIN.id}). Please
                switch your wallet.
            </p>
            <button
                className="btn mt-4"
                disabled={isPending}
                onClick={() => switchChain({chainId: TARGET_CHAIN.id})}
            >
                {isPending ? "Switching…" : `Switch to ${TARGET_CHAIN.name}`}
            </button>
        </div>
    );
}
