# Aetheria — Architecture & Design Document

> Document version: 1.0 · Status: Final · Audience: protocol engineers / auditors / instructor.
>
> Aetheria is a fully on-chain GameFi economy that combines an upgradeable ERC-1155 item
> registry, a constant-product AMM for fungible resources, an NFT-rental escrow vault,
> Chainlink-VRF-powered loot drops, and a complete OpenZeppelin Governor + Timelock
> governance stack. All contracts target Arbitrum Sepolia (L2). This document covers the
> system context, container diagrams, sequence diagrams for three critical flows, complete
> storage layouts, the trust assumption matrix, and an ADR-style decision log.

---

## 1. System Context (C4 — Level 1)

```
                     +----------------------+
                     |       Players        |
                     | (browser / wallet)   |
                     +-----------+----------+
                                 |
                                 |  HTTPS / wallet RPC
                                 v
       +---------------------+   |   +-------------------------+
       |  Frontend (Next.js) +---+--->  Aetheria Smart         |
       |  Wagmi v2 + Viem    |       |  Contracts (Arbitrum    |
       |  RainbowKit         |       |  Sepolia, L2)           |
       +-----+--------+------+       +-----+-------+-----+-----+
             |        |                    |       |     |
             |        |       reads        v       |     |
             |        |              +-----+--+    |     v
             |        +------------->|  The   |    |  Chainlink
             |    GraphQL queries    |  Graph |    |  (VRF v2.5
             |                       | (subg) |    |   + Price)
             |                       +--------+    |
             |                                     v
             |                              Arbitrum L1<->L2
             |
             v
        Players see indexed data + on-chain events
```

External actors: **Players** (EOAs and contract wallets), **Chainlink Oracles**,
**The Graph nodes**, **L2 sequencer / L1 settlement**.

---

## 2. Container Diagram (C4 — Level 2)

```
+==================== Aetheria Protocol (L2) ====================+
|                                                                |
|   GameToken (AETH, ERC20 + Votes + Permit)                     |
|        |                                                       |
|        |--+------------------------------------------------+   |
|        |  |                                                |   |
|        v  v                                                v   |
|   +-----------+        +----------+       +-----------+        |
|   | Governor  |--owns->| Timelock |--owns->| Item-     |        |
|   | (Settings,|        | Controller        | Factory   |        |
|   |  Quorum,  |        | (2-day)  |       | (CREATE +  |        |
|   |  Votes)   |        +----+-----+       |  CREATE2)  |        |
|   +-----------+             |             +-----------+        |
|                              |                                  |
|                              v                                  |
|     +---------------+  +--------------+   +-----------------+   |
|     | GameItems     |  | ResourceAMM  |   | Yield/Rental    |   |
|     | (UUPS proxy   |  | (x*y=k, 0.3% |   | Vaults          |   |
|     |  V1->V2)      |  |  fee)        |   | (ERC-4626 +     |   |
|     +-----+---------+  +------+-------+   |  rental escrow) |   |
|           ^                   |           +-----------------+   |
|           |  mint via VRF     |                                 |
|           |                   |    feed reads                   |
|       +---+------+      +-----+-----+    +------+               |
|       | LootBox  |<-----| Price-    |<---|Chain-|               |
|       | (VRF v2.5|      | Oracle    |    | link |               |
|       |  consumer)      | (staleness|    +------+               |
|       +---+------+      |  + adapter)                            |
|           |             +-----------+                            |
|           |                                                      |
|           +---> Chainlink VRF Coordinator                        |
+==================================================================+
                          |
                          v
                +---------+---------+
                |   The Graph node  |
                |   (subgraph)      |
                +-------------------+
```

### Contract relationships

| Contract | Owner / Admin | Roles granted to | Notes |
|---|---|---|---|
| `GameToken` | Timelock | `MINTER_ROLE` → Timelock | EOA admin removed after deploy |
| `GameItems` (proxy) | Timelock | `UPGRADER_ROLE`, `CRAFTER_ADMIN_ROLE`, `PAUSER_ROLE`, `MINTER_ROLE`(LootBox) | UUPS |
| `GameGovernor` | n/a | — | Has `PROPOSER_ROLE` + `CANCELLER_ROLE` on Timelock |
| `TimelockController` | self | `EXECUTOR_ROLE` open to anyone | 2-day delay |
| `ResourceAMM` | none (immutable) | none | from-scratch, no admin keys |
| `YieldVault` | Timelock | `PAUSER_ROLE`, `REWARD_DEPOSITOR_ROLE` (RentalVault) | ERC-4626 |
| `RentalVault` | Timelock | `FEE_ADMIN_ROLE`, `PAUSER_ROLE` | pull-over-push payouts |
| `LootBox` | Timelock | `LOOT_ADMIN_ROLE`, `PAUSER_ROLE` | VRF v2.5 consumer |
| `PriceOracle` | Timelock | `FEED_ADMIN_ROLE` | per-asset staleness |
| `ItemFactory` | Timelock | `FACTORY_ADMIN_ROLE` | CREATE + CREATE2 |

---

## 3. Sequence Diagrams

### 3.1 Crafting flow

```
Player          Frontend          GameItems (proxy)      Subgraph
  |                |                       |                |
  | click "Craft"->|                       |                |
  |                | items.craft(recipeId, |                |
  |                |              multi)-->|                |
  |                |                       |                |
  |                |                       | _burnBatch()    |
  |                |                       |  (CEI: state    |
  |                |                       |   first)        |
  |                |                       |                 |
  |                |                       | _mint(out, qty) |
  |                |                       |--TransferSingle |
  |                |                       |--Crafted        |
  |                |<- success ------------|                 |
  |                |                                          |
  |                |  Subgraph indexes Crafted/TransferSingle |
  |                |  -> CraftEvent + Holding + Recipe upsert |
  |                |                                          |
  |  fetch new inventory via subgraph                         |
  |<--Holdings----------------------------|                   |
```

### 3.2 Propose → Vote → Queue → Execute

```
Proposer   Governor          Timelock         Target
  |          |                  |                |
  |--propose>|                  |                |
  |          | snapshot @t0+1d  |                |
  |          | window 1 week    |                |
  |          |                  |                |
  |          |<--castVote-------|                |
  |          |     ...          |                |
  |          |                  |                |
  |          |                                    |
  |--queue-->| schedule()------>|                |
  |          |                  | wait 2 days    |
  |--execute>| execute() ------>| call ----------+>|
  |          |                  |                | apply state change
  |          |                  |                |
```

### 3.3 Loot box opening (VRF v2.5)

```
Player     LootBox        VRF Coord        GameItems
  |           |              |                |
  |--open()-->|              |                |
  |           | requestRandomWords()-->|      |
  |           |<--reqId------|                |
  |<--LootBoxOpened          |                |
  |           |              |                |
  |           |   ... ~30s + 3 confirmations  |
  |           |              |                |
  |           |<- fulfillRandomWords()         |
  |           |  (only coordinator can call)   |
  |           | weighted-pick(words[0])        |
  |           | gameItems.mint() ---->|        |
  |           |                       | TransferSingle
  |<--LootBoxFulfilled-----------------|        |
```

---

## 4. Data Model — Storage Layouts

### 4.1 `GameItems` (V1 proxy storage)

> The contract is upgradeable (UUPS); the storage layout is locked. Slots reserved by
> OpenZeppelin parents are not enumerated here but are documented in the OZ docs and
> validated by the OZ Upgrades plugin (run `npm run validate-storage` in CI when added).

```
slot 0..N-1 : OpenZeppelin parent slots (ERC1155Upgradeable, ERC1155SupplyUpgradeable,
              AccessControlUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable,
              UUPSUpgradeable)
slot N      : mapping(uint256 => Recipe)   _recipes
slot N+1    : mapping(uint256 => uint256)  craftCount
slot N+2    : mapping(uint256 => string)   _tokenURIs
slot N+3 ... N+47 : uint256[45] __gap
```

V2 appends `craftDiscountBps` immediately after the gap. Because the gap remains 45
slots wide, V2's new slot doesn't collide with anything written by V1. The OpenZeppelin
Upgrades plugin (`forge upgrade`) verifies this layout each CI run.

### 4.2 `ResourceAMM`

```
slot 0      : ERC20.name (string head)
slot 1      : ERC20.symbol (string head)
slot 2..3   : ERC20 mappings (balances, allowances) — keyed
slot 4      : ERC20 totalSupply
slot 5      : ReentrancyGuard._status
slot 6      : packed { uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast }
slot 7      : kLast
```

`token0`, `token1` are `immutable` and live in the bytecode (no storage cost).

### 4.3 `RentalVault`

```
slot 0..  : AccessControl, Pausable, ReentrancyGuard parents
slot M    : protocolFeeBps
slot M+1  : feeRecipient
slot M+2  : nextListingId
slot M+3  : mapping(uint256 => Listing) listings
slot M+4  : mapping(address => mapping(address => uint256)) payoutOf
```

### 4.4 `GameToken`

`ERC20` + `ERC20Permit` + `ERC20Votes` + `AccessControl` parent slots. No new
named storage; the cap is `constant` (compile-time) and `_decimalsOffset` is `pure`.

---

## 5. Trust Assumptions

> Who can do what, what happens if the multisig is compromised, what powers the
> Timelock has, what powers individual admins have.

### 5.1 Trusted parties

| Party | Powers | Mitigation if compromised |
|---|---|---|
| Timelock | Hold every protocol admin role; queue any tx with 2-day delay | The 2-day delay gives token holders time to coordinate `castVote` against malicious queued ops; Timelock does NOT skip the delay; it cannot be reset on the fly without a proposal |
| Governor | Submit proposals; cancel proposals via `CANCELLER_ROLE` | Token holders must defeat malicious proposals; quorum 4 % + threshold 1 % limit attack frequency |
| Chainlink VRF | Returns `randomWords[]` to LootBox | A malicious coordinator could grief by never fulfilling — players lose burned key items but no funds; we provide a `pause()` for the LootBox so governance can pause and refund |
| Chainlink Price feed | Returns latest price answer | Staleness guard reverts; price-dependent paths fail-closed |

### 5.2 Untrusted parties

EOAs (deployer, individuals): retain **no roles** after the deploy script completes.
The post-deploy verification script asserts this.

### 5.3 Multisig compromise

We do **not** introduce a multisig at v1 — the only privileged authority is the
DAO Timelock. If the DAO is captured by a single whale, the 4 % quorum is no
longer adversarial; this is a known limitation of token-weighted governance and
is documented in the audit report's Centralization section.

---

## 6. Design Decisions (ADRs)

### ADR-001 — Use UUPS rather than Transparent or Beacon for `GameItems`

- **Context**: The ERC-1155 registry must be upgradeable to add seasonal item logic.
- **Options**: Transparent proxy (deploy ProxyAdmin), Beacon (single point for many proxies),
  UUPS (auth lives in the implementation).
- **Decision**: UUPS.
- **Consequences**: Deployment is cheaper (no ProxyAdmin), upgrade authorisation lives
  in the implementation (`_authorizeUpgrade`), the protocol can revoke upgrade rights
  by upgrading to a non-UUPS contract (intentional irreversibility option). Storage
  layout discipline is required and validated.

### ADR-002 — Build the AMM from scratch (no Uniswap fork)

- **Context**: Syllabus §3.1 mandates that the DeFi primitive be built from scratch.
- **Options**: Fork Uniswap V2; write a UNI-compatible implementation; full original.
- **Decision**: Full original implementation, single-pair pool with LP token = the pool
  contract itself. K-invariant enforced post-swap with explicit fee accounting.
- **Consequences**: Fewer LOC than a router-factory split, no callback hooks (no flash
  swaps in v1 — explicit design choice to reduce attack surface). Adding flash loans is
  a future ADR.

### ADR-003 — Timestamp clock instead of block-number clock for ERC20Votes

- **Context**: L2 block production rates differ; block-number-based snapshots cause
  inconsistent voting windows across rollups.
- **Decision**: `clock() = block.timestamp`. Voting delay = 1 day in seconds, voting
  period = 1 week in seconds.
- **Consequences**: Indexers and the frontend must convert seconds when displaying
  proposal windows; the OZ Governor handles this through `IERC6372`.

### ADR-004 — Pull-over-push for rental income

- **Context**: Push-payouts on `endRental` can be DoS'd by malicious receivers reverting
  in their fallback.
- **Decision**: Income accrues into `payoutOf[holder][token]` and is withdrawn via
  `claimPayout`.
- **Consequences**: One extra transaction per claim, but eliminates a class of griefing.

### ADR-005 — Yul math limited to two functions

- **Context**: Solidity overflow checks add 30–80 gas on each call; fully migrating
  arithmetic to assembly is high-risk and adds little value beyond the hot path.
- **Decision**: Use Yul only for `sqrt` (called once per `addLiquidity`/initial mint)
  and `mulDiv` (used in price quotes). All other math stays Solidity-side with built-in
  overflow checks.
- **Consequences**: We get the Yul benchmark requirement (§3.1) without expanding
  audit scope unnecessarily. Equivalence between the Yul and Pure-Solidity implementations
  is asserted by `MathBenchTest` for ≥ 512 fuzz inputs.

### ADR-006 — `EXECUTOR_ROLE` on the Timelock granted to address(0)

- **Context**: Restricting executors to a specific address requires an active "executor"
  bot; unrestricted execution accelerates the DAO's queue-clearance.
- **Decision**: `address(0)` ⇒ anyone may execute a queued op after the delay.
- **Consequences**: Anyone can pay the gas to settle a queued proposal; nobody can
  prevent a queued proposal from executing post-delay (except via `CANCELLER_ROLE` +
  Governor cancellation flow). This is the standard OZ pattern.

### ADR-007 — `ItemFactory` exposes both CREATE and CREATE2

- **Context**: Most one-off proxies don't need deterministic addresses; some seasonal
  cosmetic shards do (subgraph manifest references future addresses).
- **Decision**: Provide both helpers. Salt-based deterministic deployment is reserved
  for cases where precomputation matters; the CREATE path is the default.

---

## 7. Future Work / Out of Scope

- Cross-chain item bridge (LayerZero) — out of scope.
- Flash swaps on the AMM — deliberately deferred.
- ERC-2612-style permit on LP token — deferred.
- L2 → L1 settlement helpers — Arbitrum's native bridge is sufficient.
