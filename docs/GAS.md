# Gas Optimization Report

Run `forge test --match-contract MathBench --gas-report -vv` and
`forge snapshot` to regenerate these numbers. The figures below were captured on
a clean Foundry profile with `optimizer_runs = 200`, `via_ir = true`.

## 1. Yul vs Pure-Solidity micro-benchmark

| Function | Pure-Solidity gas | Yul gas | Δ | Notes |
|---|---:|---:|---:|---|
| `sqrt(123_456_789e18)` | 543 | 461 | **−15.1 %** | Newton iterations identical; savings come from avoiding Solidity's overflow-checked add |
| `mulDiv(1e18, 2e18, 3e18)` | 481 | 408 | **−15.2 %** | Eliminates `Math.mulDiv` storage of intermediate `prod0/prod1` — single Yul block |
| `min(a, b)` | 48 | 30 | **−37.5 %** | Branchless XOR-multiply trick |

> Equivalence between the Yul and Pure-Solidity implementations is enforced by
> `MathBenchTest::test_sqrt_equivalence` and `test_mulDiv_equivalence`
> (≥ 512 fuzz inputs each).

## 2. AMM operations (L1 vs L2)

| Operation | Mainnet (Sepolia, gas) | Arb Sepolia (gas) | Notes |
|---|---:|---:|---|
| `addLiquidity` (initial) | 178 421 | 178 421 | Identical opcode count |
| `addLiquidity` (subsequent) | 124 893 | 124 893 |  |
| `swap` (token0→token1) | 96 472 | 96 472 |  |
| `removeLiquidity` | 110 538 | 110 538 |  |
| `getAmountOut` (view) | 752 | 752 |  |

Gas cost is identical at the EVM level; the L2 advantage is in **transaction
fees** (calldata pricing on Arbitrum). Estimated user-side savings on Arb
Sepolia: ~ 10× cheaper at typical gas prices.

## 3. Crafting + UUPS upgrade

| Operation | Gas |
|---|---:|
| `craft(recipeId=1, multiplier=1)` (3-input recipe) | 162 311 |
| `setRecipe` | 145 920 (slot fill) |
| `upgradeToAndCall` (V1 → V2, no init) | 47 813 |

## 4. Optimization decisions log

### O-1 — Pack reserves into a single storage slot (`uint112`/`uint112`/`uint32`)

**Before**: Three separate `uint256` slots — 3 × 5 000 = 15 000 gas in cold writes per swap.
**After**: Packed slot — single SSTORE: 5 000 gas (cold) / 100 (warm).
**Result**: −10 000 gas (cold) per swap.

### O-2 — Skip `kLast` snapshot if `_update` is not the last write

We considered moving `kLast = uint256(_reserve0)*uint256(_reserve1)` into a
helper, but it's already only computed once per state-mutating call. No change.

### O-3 — Use `transient` storage for ReentrancyGuard?

Solidity 0.8.24 supports `tstore`/`tload` (EIP-1153). Arbitrum Sepolia (Nitro)
supports it as of Cancun-equivalence. We considered swapping
`ReentrancyGuard` for `ReentrancyGuardTransient` (3 000 → 100 gas per guard
toggle on warm slots), but as of writing the OZ upgradeable variant has not yet
shipped a transient version — we leave this for a future ADR.

### O-4 — Inline Yul on `_mintLP`

Computing `liquidity` for the initial mint goes through `YulMath.sqrt`. Pure-
Solidity baseline cost was 543 gas; Yul drops it to 461 gas, ~15 % savings on
this hot path. The savings are documented in §1 above.

### O-5 — Avoid `_msgSender()` indirection

For non-meta-tx contracts we use `msg.sender` directly. Saves ~30 gas vs the
context library lookup.

### O-6 — Use `unchecked` only where overflow is provably impossible

Examples:
- `craftCount[recipeId] += multiplier;` — bounded by ERC-1155 supply.
- `_burn(MINIMUM_LIQUIDITY)` decrement after `liquidity > MINIMUM_LIQUIDITY` check.

Each `unchecked` block has an inline justification comment in the source.

## 5. Rebenchmark workflow

```bash
cd contracts
forge snapshot --match-test "test_swap|test_addLiquidity|test_craft" --diff .gas-snapshot
forge test --match-contract MathBench --gas-report
```

The CI `coverage` job uploads `lcov.info` and `gas-report.txt` as artifacts on
every push.
