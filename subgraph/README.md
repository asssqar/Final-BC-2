# Aetheria Subgraph

Indexes Aetheria contracts on Arbitrum Sepolia.

## Entities (≥ 4)

| Entity | Purpose |
|---|---|
| `Player` | Aggregated per-address activity |
| `Holding` | ERC-1155 balance per (player, itemId) |
| `Recipe` | On-chain crafting recipe + popularity counter |
| `CraftEvent` | Immutable craft log |
| `Swap` | AMM swap log |
| `Proposal` | Governor proposal w/ live vote tally |
| `LootBoxOpen` | VRF request + fulfilment status |

## Build

```bash
pnpm install
pnpm codegen
pnpm build
```

## Deploy (Hosted Service / Studio)

Replace the `0x000…` source addresses in `subgraph.yaml` with the actual
contract addresses from `../contracts/deployments/<chainId>.json` before
deploying:

```bash
pnpm deploy
```

## Queries

See `QUERIES.md` for the 6 documented queries used by the frontend (the
syllabus requires ≥ 5).
