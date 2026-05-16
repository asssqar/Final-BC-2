# Test Coverage

> Generated with:
> ```bash
> forge coverage --report summary --no-match-path "script/**"
> ```
> Scripts (`script/Deploy.s.sol`, `script/PostDeployVerify.s.sol`) are excluded —
> they are integration/deployment scripts, not library code, and are not executed by the test suite.
> CI uploads `lcov.info` as an artifact on every push.

## Latest snapshot

```
| File                                          | % Lines        | % Statements   | % Branches    | % Funcs        |
|-----------------------------------------------|----------------|----------------|---------------|----------------|
| src/amm/ResourceAMM.sol                       | 89.76% (114/127)| 87.36% (152/174)| 47.22% (17/36)| 100.00% (14/14)|
| src/factory/ItemFactory.sol                   | 100.00% (14/14)| 100.00% (13/13)| 50.00% (1/2)  | 100.00% (4/4)  |
| src/governance/GameGovernor.sol               | 100.00% (22/22)| 100.00% (22/22)| 100.00% (0/0) | 100.00% (11/11)|
| src/libs/PureMath.sol                         | 94.59% (35/37) | 95.74% (45/47) | 88.89% (8/9)  | 100.00% (3/3)  |
| src/libs/YulMath.sol                          | 100.00% (61/61)| 100.00% (65/65)| 100.00% (13/13)| 100.00% (3/3) |
| src/loot/LootBox.sol                          | 100.00% (56/56)| 100.00% (58/58)| 100.00% (7/7) | 100.00% (9/9)  |
| src/oracles/MockAggregator.sol                | 100.00% (21/21)| 100.00% (13/13)| 100.00% (0/0) | 100.00% (8/8)  |
| src/oracles/PriceOracle.sol                   | 100.00% (30/30)| 97.22% (35/36) | 91.67% (11/12)| 100.00% (5/5)  |
| src/tokens/GameItems.sol                      | 85.19% (69/81) | 81.61% (71/87) | 58.33% (7/12) | 78.95% (15/19) |
| src/tokens/GameToken.sol                      | 100.00% (19/19)| 100.00% (16/16)| 100.00% (2/2) | 100.00% (7/7)  |
| src/upgrades/GameItemsV2.sol                  | 100.00% (32/32)| 90.70% (39/43) | 42.86% (3/7)  | 100.00% (3/3)  |
| src/vaults/RentalVault.sol                    | 96.10% (74/77) | 97.83% (90/92) | 100.00% (13/13)| 92.31% (12/13)|
| src/vaults/YieldVault.sol                     | 100.00% (20/20)| 100.00% (15/15)| 100.00% (0/0) | 100.00% (9/9)  |
| test/gas/MathBench.t.sol                      | 100.00% (8/8)  | 100.00% (8/8)  | 100.00% (0/0) | 100.00% (4/4)  |
| test/helpers/Fixtures.sol                     | 0.00% (0/33)   | 0.00% (0/33)   | 100.00% (0/0) | 0.00% (0/3)    |
| test/invariant/AMM.invariant.t.sol            | 100.00% (31/31)| 96.97% (32/33) | 0.00% (0/1)   | 100.00% (4/4)  |
| test/invariant/Token.invariant.t.sol          | 100.00% (20/20)| 100.00% (15/15)| 100.00% (0/0) | 100.00% (5/5)  |
| test/invariant/Vault.invariant.t.sol          | 100.00% (18/18)| 100.00% (18/18)| 100.00% (2/2) | 100.00% (3/3)  |
| test/security/Reentrancy.t.sol                | 76.47% (13/17) | 78.57% (11/14) | 100.00% (2/2) | 60.00% (3/5)   |
| test/unit/CoverageExtended.t.sol              | 100.00% (6/6)  | 100.00% (8/8)  | 100.00% (0/0) | 100.00% (5/5)  |
| test/unit/VRFCoordinatorV2_5Mock.sol          | 100.00% (14/14)| 100.00% (10/10)| 75.00% (3/4)  | 100.00% (5/5)  |
| test/unit/YulMath.t.sol                       | 100.00% (6/6)  | 100.00% (6/6)  | 100.00% (0/0) | 100.00% (3/3)  |
|-----------------------------------------------|----------------|----------------|---------------|----------------|
| TOTAL                                         | 91.07% (683/750)| 89.83% (742/826)| 72.95% (89/122)| 93.10% (135/145)|
```

> **Line coverage 91.07% ≥ 90%** required by §3.3. ✅

## Test counts

```
Unit tests        : 80
Fuzz tests        : 11
Invariant tests   :  6
Fork tests        :  4
Security tests    :  7
Gas/Math benches  :  3
TOTAL             : 111
```

All tests pass. CI fails the build if any test reverts.
