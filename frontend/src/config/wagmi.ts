import {getDefaultConfig} from "@rainbow-me/rainbowkit";
import {arbitrumSepolia} from "wagmi/chains";
import {http} from "viem";

export const ARB_SEPOLIA_RPC =
    process.env.NEXT_PUBLIC_ARB_SEPOLIA_RPC ?? "https://sepolia-rollup.arbitrum.io/rpc";

export const wagmiConfig = getDefaultConfig({
    appName: "Aetheria",
    projectId: process.env.NEXT_PUBLIC_WALLETCONNECT_ID ?? "FILL_ME",
    chains: [arbitrumSepolia],
    transports: {
        [arbitrumSepolia.id]: http(ARB_SEPOLIA_RPC),
    },
    ssr: true,
});

export const TARGET_CHAIN = arbitrumSepolia;
