# Final Presentation — Aetheria GameFi Economy

> 15-minute live presentation + 10-minute Q&A. Each member presents a segment.
> Slide deck (PDF) is exported from this outline.

---

## Slide 1 — Title

- **Aetheria — A DAO-governed GameFi economy on Arbitrum L2**
- Team A, B, C
- Course: Blockchain Technologies 2 — Final Project (Option B)

## Slide 2 — Problem & Vision

- Most "GameFi" experiments couple game logic tightly to a single, mutable token —
  no upgrade story, no governance, oracle-free randomness.
- Aetheria treats the in-game economy as a real protocol: upgradeable items,
  trustless trading, on-chain rentals, verifiable randomness, on-chain governance.

## Slide 3 — System Map

- (Insert C4 Container diagram — see `docs/ARCHITECTURE.md` §2)
- 12 contracts on Arbitrum Sepolia.
- One off-chain dependency we don't trust unilaterally (Chainlink) — gated behind
  staleness + adapter pattern.

## Slide 4 — Demo agenda

1. Connect wallet → see balance + voting power (subgraph + on-chain).
2. Add liquidity to AMM → swap.
3. Open a loot box → VRF callback mints item.
4. Submit, vote, queue, execute a governance proposal that flips a craft fee.
5. Upgrade `GameItems` V1 → V2 via Timelock-queued upgrade.

## Slide 5 — Smart contracts overview (Member A)

- Tokens: `GameToken` (ERC20Votes+Permit, capped 100M), `GameItems` UUPS ERC-1155.
- Crafting state machine + recipe cache.
- AMM from scratch — uniswap-V2 math but no router.
- Yul math benchmark — 15 % savings on `sqrt`/`mulDiv`, equivalence-tested.

## Slide 6 — Vaults & Rentals (Member A)

- ERC-4626 yield vault — donation-attack mitigation via 6-decimal offset.
- Rental vault — pull-over-push accounting, escrowed ERC-1155, governance-tunable
  protocol fee capped at 10 %.

## Slide 7 — Oracles & VRF (Member B)

- `PriceOracle` adapter: per-asset feed registration + staleness + scaling to 1e18.
- `LootBox` consumer of Chainlink VRF v2.5: keyed by ERC-1155 burn, weighted
  reward table, callback only from coordinator.

## Slide 8 — Governance (Member B)

- Full OZ Governor stack — 1-day delay, 1-week period, 4 % quorum, 1 % threshold.
- Timelock with **2-day delay** owns every privileged path.
- Demo: a live proposal end-to-end.

## Slide 9 — Security (Member B)

- Slither: 0 High, 0 Medium.
- 2 reproduced-and-fixed cases (reentrancy, access control).
- Centralisation matrix: deployer holds 0 roles after deploy (verified by script).
- Known limitations: token-weighted DAO can be captured by a whale — exit window via
  2-day timelock.

## Slide 10 — Tests (Member C)

- 111 tests total (80 unit + 11 fuzz + 6 invariant + 4 fork + 7 security + 3 bench).
- ≥ 95.9 % line coverage; CI fails on any regression.
- Invariants: k never decreases, reserves match balances, vault solvency, supply
  conservation.

## Slide 11 — Frontend & subgraph (Member C)

- Next.js 14 + Wagmi v2 + Viem + RainbowKit.
- 5 pages: Home, Swap, Vault, Governance, LootBox, Leaderboard.
- Subgraph: 7 entities, 6 documented queries; one page (Leaderboard) reads
  *exclusively* from The Graph.

## Slide 12 — Deployment (Member C)

- Single idempotent deploy script — outputs `deployments/<chainId>.json`.
- Post-deploy verification script asserts every governance invariant
  (Timelock delay, Governor params, no EOA admin).
- Verified contracts on Arbiscan — links in the README.

## Slide 13 — Gas optimisation (Member A)

- Yul math saves ~15 %.
- Reserve packing (uint112+uint112+uint32) saves ~10k gas per cold swap.
- Documented decision log in `docs/GAS.md`.

## Slide 14 — What we'd build next

- ERC-2612 LP permit, flash swaps.
- Cross-chain item bridge (LayerZero).
- Replace ReentrancyGuard with the EIP-1153 transient variant once OZ ships it.

## Slide 15 — Q&A
