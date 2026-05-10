# Aetheria — GameFi Economy Protocol

> Final project for **Blockchain Technologies 2** (Option B — GameFi Economy).
>
> Aetheria is a production-grade, DAO-governed, L2-deployed in-game economy.
> Players craft items from on-chain resources, trade fungible resources on a
> from-scratch AMM, rent NFTs, and open VRF-powered loot boxes — all
> parameterised by a fully on-chain Governor + Timelock stack.

---

## Repository Layout

```
.
├── contracts/          Foundry project (Solidity 0.8.24)
│   ├── src/            Production contracts (upgradeable + non-upgradeable)
│   ├── script/         Deployment + post-deploy verification scripts
│   └── test/           Unit / fuzz / invariant / fork / security tests
├── frontend/           Next.js 14 dApp (Wagmi v2 + Viem + RainbowKit)
├── subgraph/           The Graph subgraph (4 entities, 5 documented queries)
├── docs/
│   ├── ARCHITECTURE.md     System design, C4 diagrams, ADRs (≥6 pages)
│   ├── AUDIT.md            Internal audit report (≥8 pages)
│   ├── GAS.md              Before/after gas optimisation report
│   ├── COVERAGE.md         forge-coverage snapshot
│   └── PRESENTATION.md     Final presentation outline (slide-by-slide)
└── .github/workflows/  CI pipelines (build, test, coverage, slither, lint)
```

---

## Mandatory Requirements — Coverage Map

| § | Requirement | Where it lives |
|---|---|---|
| 3.1 | UUPS upgradeable contract + V1→V2 path | `src/tokens/GameItems.sol` + `src/upgrades/GameItemsV2.sol` |
| 3.1 | Factory using CREATE & CREATE2 | `src/factory/ItemFactory.sol` |
| 3.1 | Inline Yul vs pure-Solidity benchmark | `src/libs/YulMath.sol` + `src/libs/PureMath.sol` + `test/gas/MathBench.t.sol` |
| 3.1 | ERC-20 governance (Votes + Permit) | `src/tokens/GameToken.sol` |
| 3.1 | ERC-1155 with crafting | `src/tokens/GameItems.sol` |
| 3.1 | ERC-4626 vault (rounding-safe) | `src/vaults/YieldVault.sol` |
| 3.1 | x·y=k AMM, 0.3% fee, LP tokens, slippage guard, from scratch | `src/amm/ResourceAMM.sol` |
| 3.1 | Chainlink price feed + staleness + mock | `src/oracles/PriceOracle.sol`, `src/oracles/MockAggregator.sol` |
| 3.1 | Chainlink VRF for loot drops | `src/loot/LootBox.sol` |
| 3.1 | Subgraph with ≥4 entities, ≥5 queries | `subgraph/` |
| 3.1 | Governor + Timelock(2d) + ERC20Votes, vote delay 1d, period 1w, quorum 4%, threshold 1% | `src/governance/GameGovernor.sol` + `script/Deploy.s.sol` |
| 3.1 | L2 deployment + verification | Arbitrum Sepolia (addresses & explorer links below) |
| 3.2 | CEI / ReentrancyGuard documented | `docs/AUDIT.md` |
| 3.2 | OZ AccessControl on every privileged path | every contract; matrix in `docs/AUDIT.md` |
| 3.2 | Slither: 0 High / 0 Medium | `docs/AUDIT.md` (appendix) |
| 3.2 | 2 reproduced-and-fixed vulnerabilities | `test/security/Reentrancy.t.sol`, `test/security/AccessControl.t.sol` |
| 3.2 | No `tx.origin`, no `block.timestamp` randomness, no `transfer/send` | enforced by `slither` config |
| 3.2 | SafeERC20 everywhere | grep clean — see CI |
| 3.3 | ≥50 unit + ≥10 fuzz + ≥5 invariant + ≥3 fork tests | `contracts/test/` |
| 3.3 | ≥90% line coverage | `docs/COVERAGE.md` |
| 3.4 | Wallet, balances, votes, 3+ writes, proposals, subgraph reads, error UX, network detect | `frontend/` |
| 3.5 | CI on every push/PR | `.github/workflows/ci.yml` |
| 3.5 | `forge fmt --check`, `solhint`, `prettier` in CI | same |
| 3.5 | Deploy script + verification | `contracts/script/Deploy.s.sol` |

---

## Quick Start

```bash
# 1) Install toolchain
curl -L https://foundry.paradigm.xyz | bash && foundryup
npm i -g pnpm

# 2) Build & test contracts
cd contracts
forge install
forge build
forge test -vv
forge coverage --report summary

# 3) Run frontend
cd ../frontend
pnpm install
pnpm dev   # http://localhost:3000

# 4) Subgraph
cd ../subgraph
pnpm install
pnpm codegen && pnpm build
```

---

## Deployment (Arbitrum Sepolia, chainId 421614)

| Contract | Address |
|---|---|
| `GameToken` (ERC20Votes+Permit) | `0x_FILL_AFTER_DEPLOY` |
| `TimelockController` | `0x_FILL_AFTER_DEPLOY` |
| `GameGovernor` | `0x_FILL_AFTER_DEPLOY` |
| `GameItemsProxy` (UUPS, V1) | `0x_FILL_AFTER_DEPLOY` |
| `GameItemsImpl` (V1) | `0x_FILL_AFTER_DEPLOY` |
| `GameItemsImplV2` | `0x_FILL_AFTER_DEPLOY` |
| `ResourceAMM` (Wood/Iron) | `0x_FILL_AFTER_DEPLOY` |
| `YieldVault` (ERC4626) | `0x_FILL_AFTER_DEPLOY` |
| `RentalVault` | `0x_FILL_AFTER_DEPLOY` |
| `LootBox` (VRF) | `0x_FILL_AFTER_DEPLOY` |
| `PriceOracle` | `0x_FILL_AFTER_DEPLOY` |
| `ItemFactory` | `0x_FILL_AFTER_DEPLOY` |

The deploy script at `contracts/script/Deploy.s.sol` writes all addresses into
`contracts/deployments/<chainId>.json`, which is consumed by the frontend and
the subgraph manifest. Verification is performed automatically with
`--verify --etherscan-api-key $ARBISCAN_API_KEY`.

After deployment, run the post-deploy verification script:

```bash
forge script script/PostDeployVerify.s.sol --rpc-url $ARB_SEPOLIA_RPC -vvvv
```

It asserts:
- `GameItemsProxy.owner() == TimelockController`
- `TimelockController.getMinDelay() == 2 days`
- `Governor.votingDelay() == 1 day`, `votingPeriod() == 1 week`, `quorumNumerator() == 4`, `proposalThreshold() == 1%`
- No EOA retains `DEFAULT_ADMIN_ROLE` on any contract.

---

## Team & Ownership

> Team composition is final. Each member is individually accountable for
> every part of the codebase per the syllabus.

| Member | Primary ownership | Secondary |
|---|---|---|
| Member A | Smart contracts (tokens, AMM, vaults) | Tests |
| Member B | Governance, oracles, VRF, factory, security audit | DevOps |
| Member C | Frontend, subgraph, deployment scripts, docs | Tests |

(Update with real names before submission.)

---

## License

MIT — see `LICENSE`.
# Final-BC-2
