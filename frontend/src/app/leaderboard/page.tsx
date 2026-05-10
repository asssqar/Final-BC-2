"use client";
import {Header} from "@/components/Header";
import {NetworkGuard} from "@/components/NetworkGuard";
import {subgraphClient} from "@/lib/subgraph";
import {TOP_CRAFTERS} from "@/lib/queries";
import {useEffect, useState} from "react";

interface PlayerRow {
    id: string;
    address: string;
    totalCrafted: string;
    totalLootBoxes: string;
}

export default function LeaderboardPage() {
    const [players, setPlayers] = useState<PlayerRow[]>([]);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        let mounted = true;
        (async () => {
            try {
                const r = await subgraphClient.query(TOP_CRAFTERS, {}).toPromise();
                if (!mounted) return;
                setPlayers((r.data?.players ?? []) as PlayerRow[]);
            } finally {
                if (mounted) setLoading(false);
            }
        })();
        return () => {
            mounted = false;
        };
    }, []);

    return (
        <>
            <Header />
            <main className="max-w-3xl mx-auto px-6 py-10">
                <NetworkGuard>
                    <h1 className="text-2xl font-semibold mb-4">Top Crafters</h1>
                    <p className="text-sm text-aether-700 mb-4">
                        Indexed by The Graph — direct subgraph read, not contract call.
                    </p>
                    {loading && <div>Loading…</div>}
                    {!loading && players.length === 0 && (
                        <div className="text-aether-700">No data yet.</div>
                    )}
                    <table className="w-full text-sm">
                        <thead className="text-aether-700 text-left">
                            <tr>
                                <th className="py-2">#</th>
                                <th>Address</th>
                                <th>Crafted</th>
                                <th>Loot</th>
                            </tr>
                        </thead>
                        <tbody>
                            {players.map((p, i) => (
                                <tr key={p.id} className="border-t border-aether-100">
                                    <td className="py-2">{i + 1}</td>
                                    <td className="font-mono">
                                        {p.address.slice(0, 6)}…{p.address.slice(-4)}
                                    </td>
                                    <td>{p.totalCrafted}</td>
                                    <td>{p.totalLootBoxes}</td>
                                </tr>
                            ))}
                        </tbody>
                    </table>
                </NetworkGuard>
            </main>
        </>
    );
}
