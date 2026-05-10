import type {Metadata} from "next";
import "./globals.css";
import {Providers} from "./providers";

export const metadata: Metadata = {
    title: "Aetheria — GameFi Economy",
    description:
        "DAO-governed in-game economy: crafting, AMM, NFT rentals, VRF loot, on Arbitrum Sepolia.",
};

export default function RootLayout({children}: {children: React.ReactNode}) {
    return (
        <html lang="en">
            <body className="bg-aether-50 text-aether-900 min-h-screen">
                <Providers>{children}</Providers>
            </body>
        </html>
    );
}
