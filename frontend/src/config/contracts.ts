/**
 * Contract addresses & shared ABIs.
 *
 * Addresses are loaded from `contracts/deployments/<chainId>.json` at build time.
 * For local development before deployment, set the keys to "0x0" — the UI gracefully
 * detects an unconfigured environment and shows a banner.
 */
import type {Address} from "viem";
import deployment from "../../../contracts/deployments/421614.json" assert {type: "json"};

export interface DeploymentConfig {
    gameToken: Address;
    timelock: Address;
    governor: Address;
    gameItemsProxy: Address;
    gameItemsImpl: Address;
    resourceA: Address;
    resourceB: Address;
    amm: Address;
    yieldVault: Address;
    rentalVault: Address;
    lootBox: Address;
    priceOracle: Address;
    itemFactory: Address;
}

export const CONTRACTS: DeploymentConfig = deployment as DeploymentConfig;

export const ZERO: Address = "0x0000000000000000000000000000000000000000";

export const isUnconfigured = Object.values(CONTRACTS).some((a) => a === ZERO || !a);
