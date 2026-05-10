"use client";
import {ConnectButton} from "@rainbow-me/rainbowkit";
import Link from "next/link";

export function Header() {
    return (
        <header className="border-b border-aether-100 bg-white sticky top-0 z-10">
            <div className="max-w-6xl mx-auto px-6 py-4 flex items-center justify-between">
                <Link href="/" className="flex items-center gap-2">
                    <span className="text-2xl">⚔️</span>
                    <span className="text-xl font-semibold text-aether-700">Aetheria</span>
                </Link>
                <nav className="hidden md:flex gap-6 text-sm font-medium text-aether-700">
                    <Link href="/swap" className="hover:underline">
                        Swap
                    </Link>
                    <Link href="/vault" className="hover:underline">
                        Vault
                    </Link>
                    <Link href="/governance" className="hover:underline">
                        Governance
                    </Link>
                    <Link href="/lootbox" className="hover:underline">
                        Loot
                    </Link>
                    <Link href="/leaderboard" className="hover:underline">
                        Leaderboard
                    </Link>
                </nav>
                <ConnectButton />
            </div>
        </header>
    );
}
