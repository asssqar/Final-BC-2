# SETUP — one-time installation

```bash
# 1) Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# 2) Node (pnpm preferred)
corepack enable
corepack prepare pnpm@latest --activate

# 3) Install dependencies
cd contracts
forge install OpenZeppelin/openzeppelin-contracts@v5.0.2 --no-commit
forge install OpenZeppelin/openzeppelin-contracts-upgradeable@v5.0.2 --no-commit
forge install smartcontractkit/chainlink@v2.13.0 --no-commit
forge install foundry-rs/forge-std@v1.9.3 --no-commit

# 4) Build & test
forge build
forge test -vv

# 5) Frontend
cd ../frontend
pnpm install
cp .env.example .env.local
# fill NEXT_PUBLIC_WALLETCONNECT_ID, NEXT_PUBLIC_SUBGRAPH_URL
pnpm dev

# 6) Subgraph
cd ../subgraph
pnpm install
# After contracts are built and deployed:
./scripts/copy-abis.sh
pnpm codegen
pnpm build
```

## Deploying to Arbitrum Sepolia

```bash
cd contracts
cp .env.example .env
# fill DEPLOYER_PRIVATE_KEY, ARB_SEPOLIA_RPC, VRF_*, ARBISCAN_API_KEY

source .env
forge script script/Deploy.s.sol \
    --rpc-url $ARB_SEPOLIA_RPC \
    --broadcast \
    --verify \
    --etherscan-api-key $ARBISCAN_API_KEY \
    -vvvv

# Post-deploy assertions
DEPLOYER_ADDRESS=$(cast wallet address $DEPLOYER_PRIVATE_KEY) \
forge script script/PostDeployVerify.s.sol --rpc-url $ARB_SEPOLIA_RPC -vvvv
```

After deployment:

- `contracts/deployments/421614.json` is updated automatically.
- The frontend imports that file at build time (`pnpm build` or `pnpm dev`).
- For the subgraph: copy contract addresses into `subgraph/subgraph.yaml` (the
  `source.address` fields), run `./scripts/copy-abis.sh`, then `pnpm codegen && pnpm build`.

## Running specific test groups

```bash
cd contracts

# Unit + fuzz + invariant + security (no fork)
forge test -vv --no-match-path "test/fork/**"

# Coverage report
forge coverage --report summary --no-match-path "test/fork/**"

# Gas report (incl. Yul vs Pure-Solidity benchmark)
forge test --match-contract MathBench --gas-report

# Fork tests (requires MAINNET_RPC + ARB_SEPOLIA_RPC env vars)
forge test --match-path "test/fork/**" -vv

# Slither
slither . --config-file slither.config.json
```
