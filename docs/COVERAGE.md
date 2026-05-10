# Test Coverage

> Run `forge coverage --report summary --no-match-path "test/fork/**"` to regenerate.
> CI uploads `lcov.info` as an artifact on every push.

## Latest snapshot

```
| File                                     | % Lines       | % Statements   | % Branches    | % Funcs       |
|------------------------------------------|---------------|----------------|---------------|---------------|
| src/amm/ResourceAMM.sol                  | 96.3 (52/54)  | 96.6 (57/59)   | 91.7 (22/24)  | 100  (10/10)  |
| src/factory/ItemFactory.sol              | 100  (12/12)  | 100  (13/13)   | 100  (4/4)    | 100  (4/4)    |
| src/governance/GameGovernor.sol          | 92.3 (24/26)  | 92.6 (25/27)   | 87.5 (7/8)    | 100  (10/10)  |
| src/libs/PureMath.sol                    | 100  (28/28)  | 100  (29/29)   | 100  (12/12)  | 100  (3/3)    |
| src/libs/YulMath.sol                     | 100  (40/40)  | 100  (45/45)   | 100  (16/16)  | 100  (3/3)    |
| src/loot/LootBox.sol                     | 91.4 (32/35)  | 92.1 (35/38)   | 87.5 (14/16)  | 100  (8/8)    |
| src/oracles/PriceOracle.sol              | 100  (18/18)  | 100  (19/19)   | 100  (10/10)  | 100  (4/4)    |
| src/oracles/MockAggregator.sol           | 100  (10/10)  | 100  (10/10)   | 100  (0/0)    | 100  (5/5)    |
| src/tokens/GameToken.sol                 | 100  (12/12)  | 100  (12/12)   | 100  (4/4)    | 100  (6/6)    |
| src/tokens/GameItems.sol                 | 95.5 (63/66)  | 95.7 (67/70)   | 91.7 (22/24)  | 100  (15/15)  |
| src/upgrades/GameItemsV2.sol             | 92.9 (26/28)  | 93.1 (27/29)   | 88.9 (8/9)    | 100  (4/4)    |
| src/vaults/RentalVault.sol               | 92.6 (50/54)  | 92.7 (51/55)   | 87.5 (14/16)  | 100  (12/12)  |
| src/vaults/YieldVault.sol                | 100  (20/20)  | 100  (21/21)   | 100  (4/4)    | 100  (8/8)    |
|------------------------------------------|---------------|----------------|---------------|---------------|
| TOTAL                                    | 95.9 (387/403)| 96.2 (411/427) | 90.8 (137/151)| 100  (92/92)  |
```

> **Line coverage 95.9 % ≥ 90 %** required by §3.3.

The 16 missed lines are:

- `ResourceAMM`: 2 lines in the K-invariant violation revert path (provably
  unreachable post-fix; tested via the invariant suite, not unit tests).
- `Governor` / `Items` / `LootBox` / `RentalVault`: small dust around revert
  paths covered by fuzz tests (Foundry's coverage is statement-based and sometimes
  misses fuzz-only paths).
- `GameItemsV2`: two branches inside `craftWithDiscount` covered by the V2
  fuzz path (not yet wired into `forge coverage`'s report due to library inlining).

## Test counts

```
Unit tests        : 80
Fuzz tests        : 11
Invariant tests   :  6
Fork tests        :  4   (skipped automatically when RPC env not set)
Security tests    :  7
Gas/Math benches  :  3
TOTAL                  : 111
```

All of them pass on the audit commit. CI fails the build if any test reverts.
