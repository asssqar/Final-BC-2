"use client";
import {WagmiProvider} from "wagmi";
import {RainbowKitProvider} from "@rainbow-me/rainbowkit";
import "@rainbow-me/rainbowkit/styles.css";
import {QueryClient, QueryClientProvider} from "@tanstack/react-query";
import {wagmiConfig} from "@/config/wagmi";
import {ReactNode, useState} from "react";

export function Providers({children}: {children: ReactNode}) {
    const [queryClient] = useState(() => new QueryClient());
    return (
        <WagmiProvider config={wagmiConfig}>
            <QueryClientProvider client={queryClient}>
                <RainbowKitProvider>{children}</RainbowKitProvider>
            </QueryClientProvider>
        </WagmiProvider>
    );
}
