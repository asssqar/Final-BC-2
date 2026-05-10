// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

import {GameToken} from "../src/tokens/GameToken.sol";
import {GameItems} from "../src/tokens/GameItems.sol";
import {ResourceAMM} from "../src/amm/ResourceAMM.sol";
import {YieldVault} from "../src/vaults/YieldVault.sol";
import {RentalVault} from "../src/vaults/RentalVault.sol";
import {LootBox} from "../src/loot/LootBox.sol";
import {PriceOracle} from "../src/oracles/PriceOracle.sol";
import {MockAggregator} from "../src/oracles/MockAggregator.sol";
import {ItemFactory} from "../src/factory/ItemFactory.sol";
import {GameGovernor} from "../src/governance/GameGovernor.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IGameItems} from "../src/interfaces/IGameItems.sol";

/// @title Deploy
/// @notice Idempotent, parameterised deployment script. Outputs addresses to
///         `deployments/<chainId>.json` for the frontend & subgraph.
///
/// Required env vars:
///   DEPLOYER_PRIVATE_KEY         - deployer's private key (broadcast)
///   VRF_COORDINATOR              - Chainlink VRF v2.5 coordinator on the target chain
///   VRF_KEY_HASH                 - VRF key hash
///   VRF_SUBSCRIPTION_ID          - subscription id (uint256)
///   ETH_USD_FEED                 - Chainlink price feed address (or 0x0 → deploy mock)
///
/// Usage:
///   forge script script/Deploy.s.sol --rpc-url $ARB_SEPOLIA_RPC --broadcast --verify
contract Deploy is Script {
    struct Deployed {
        address gameToken;
        address timelock;
        address governor;
        address gameItemsImpl;
        address gameItemsProxy;
        address resourceA;
        address resourceB;
        address amm;
        address yieldVault;
        address rentalVault;
        address lootBox;
        address priceOracle;
        address itemFactory;
    }

    function run() external returns (Deployed memory d) {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(pk);
        vm.startBroadcast(pk);

        // -------------------------------------------------------------------
        // 1. Governance token
        // -------------------------------------------------------------------
        GameToken token = new GameToken(deployer, deployer, 10_000_000e18);
        d.gameToken = address(token);

        // -------------------------------------------------------------------
        // 2. Timelock (2-day delay) + Governor
        // -------------------------------------------------------------------
        address[] memory empty = new address[](0);
        TimelockController timelock = new TimelockController(2 days, empty, empty, deployer);
        d.timelock = address(timelock);

        GameGovernor governor = new GameGovernor(IVotes(address(token)), timelock);
        d.governor = address(governor);

        // Wire roles so only the Governor can propose, anyone can execute.
        bytes32 PROPOSER_ROLE = timelock.PROPOSER_ROLE();
        bytes32 EXECUTOR_ROLE = timelock.EXECUTOR_ROLE();
        bytes32 CANCELLER_ROLE = timelock.CANCELLER_ROLE();
        bytes32 TIMELOCK_ADMIN = timelock.DEFAULT_ADMIN_ROLE();

        timelock.grantRole(PROPOSER_ROLE, address(governor));
        timelock.grantRole(EXECUTOR_ROLE, address(0));
        timelock.grantRole(CANCELLER_ROLE, address(governor));

        // -------------------------------------------------------------------
        // 3. GameItems (UUPS proxy)
        // -------------------------------------------------------------------
        GameItems impl = new GameItems();
        d.gameItemsImpl = address(impl);
        bytes memory initData = abi.encodeCall(GameItems.initialize, (deployer, "ipfs://aetheria/{id}.json"));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        d.gameItemsProxy = address(proxy);

        GameItems items = GameItems(address(proxy));

        // -------------------------------------------------------------------
        // 4. Two ERC-20 resources for the AMM (Wood, Iron). Use lightweight
        //    test tokens that mirror GameToken — they're separate addresses
        //    so the AMM has real assets to swap.
        // -------------------------------------------------------------------
        GameToken wood = new GameToken(deployer, deployer, 1_000_000e18);
        GameToken iron = new GameToken(deployer, deployer, 1_000_000e18);
        d.resourceA = address(wood);
        d.resourceB = address(iron);

        ResourceAMM amm = new ResourceAMM(IERC20(address(wood)), IERC20(address(iron)));
        d.amm = address(amm);

        // -------------------------------------------------------------------
        // 5. YieldVault, RentalVault, PriceOracle, ItemFactory
        // -------------------------------------------------------------------
        YieldVault vault = new YieldVault(IERC20(address(token)), deployer);
        d.yieldVault = address(vault);

        RentalVault rentals = new RentalVault(deployer, address(vault));
        d.rentalVault = address(rentals);

        PriceOracle oracle = new PriceOracle(deployer);
        address ethUsdFeed = vm.envOr("ETH_USD_FEED", address(0));
        if (ethUsdFeed == address(0)) {
            MockAggregator mock = new MockAggregator(2_000e8, 8); // $2,000
            ethUsdFeed = address(mock);
        }
        oracle.setFeed(address(token), ethUsdFeed, 1 hours);
        d.priceOracle = address(oracle);

        ItemFactory factory = new ItemFactory(deployer);
        d.itemFactory = address(factory);

        // -------------------------------------------------------------------
        // 6. LootBox (Chainlink VRF v2.5)
        // -------------------------------------------------------------------
        address vrfCoord = vm.envAddress("VRF_COORDINATOR");
        bytes32 keyHash = vm.envBytes32("VRF_KEY_HASH");
        uint256 subId = vm.envUint("VRF_SUBSCRIPTION_ID");
        LootBox lootBox = new LootBox(vrfCoord, keyHash, subId, IGameItems(address(items)), deployer);
        d.lootBox = address(lootBox);

        // -------------------------------------------------------------------
        // 7. Wire roles: grant LootBox MINTER_ROLE on GameItems + reward table.
        // -------------------------------------------------------------------
        items.grantRole(items.MINTER_ROLE(), address(lootBox));

        LootBox.Reward[] memory rewards = new LootBox.Reward[](3);
        rewards[0] = LootBox.Reward({itemId: 1, amount: 5, weight: 6_000});  // 60 % common
        rewards[1] = LootBox.Reward({itemId: 2, amount: 1, weight: 3_000});  // 30 % rare
        rewards[2] = LootBox.Reward({itemId: 3, amount: 1, weight: 1_000});  // 10 % epic
        lootBox.setRewards(rewards);
        lootBox.setKeyItem(0, 0);

        // Set a sample crafting recipe (2 wood + 1 iron → 1 sword).
        items.grantRole(items.MINTER_ROLE(), deployer); // for one-time seed mints
        items.mint(deployer, 1, 1_000, "");
        items.mint(deployer, 2, 1_000, "");

        uint256[] memory inIds = new uint256[](2);
        inIds[0] = 1;
        inIds[1] = 2;
        uint256[] memory inAmts = new uint256[](2);
        inAmts[0] = 2;
        inAmts[1] = 1;
        items.setRecipe(1, inIds, inAmts, 1_000, 1, 0);

        // -------------------------------------------------------------------
        // 8. Hand off all admin powers to the Timelock.
        // -------------------------------------------------------------------
        // GameItems
        items.grantRole(items.DEFAULT_ADMIN_ROLE(), address(timelock));
        items.grantRole(items.UPGRADER_ROLE(), address(timelock));
        items.grantRole(items.CRAFTER_ADMIN_ROLE(), address(timelock));
        items.grantRole(items.PAUSER_ROLE(), address(timelock));
        items.revokeRole(items.UPGRADER_ROLE(), deployer);
        items.revokeRole(items.CRAFTER_ADMIN_ROLE(), deployer);
        items.revokeRole(items.PAUSER_ROLE(), deployer);
        items.revokeRole(items.MINTER_ROLE(), deployer);
        items.revokeRole(items.DEFAULT_ADMIN_ROLE(), deployer);

        // GameToken — minter goes to timelock
        token.grantRole(token.MINTER_ROLE(), address(timelock));
        token.grantRole(token.DEFAULT_ADMIN_ROLE(), address(timelock));
        token.revokeRole(token.MINTER_ROLE(), deployer);
        token.revokeRole(token.DEFAULT_ADMIN_ROLE(), deployer);

        // YieldVault
        vault.grantRole(vault.DEFAULT_ADMIN_ROLE(), address(timelock));
        vault.grantRole(vault.PAUSER_ROLE(), address(timelock));
        vault.grantRole(vault.REWARD_DEPOSITOR_ROLE(), address(rentals)); // RentalVault forwards fees
        vault.revokeRole(vault.PAUSER_ROLE(), deployer);
        vault.revokeRole(vault.DEFAULT_ADMIN_ROLE(), deployer);

        // RentalVault
        rentals.grantRole(rentals.DEFAULT_ADMIN_ROLE(), address(timelock));
        rentals.grantRole(rentals.PAUSER_ROLE(), address(timelock));
        rentals.grantRole(rentals.FEE_ADMIN_ROLE(), address(timelock));
        rentals.revokeRole(rentals.FEE_ADMIN_ROLE(), deployer);
        rentals.revokeRole(rentals.PAUSER_ROLE(), deployer);
        rentals.revokeRole(rentals.DEFAULT_ADMIN_ROLE(), deployer);

        // PriceOracle
        oracle.grantRole(oracle.DEFAULT_ADMIN_ROLE(), address(timelock));
        oracle.grantRole(oracle.FEED_ADMIN_ROLE(), address(timelock));
        oracle.revokeRole(oracle.FEED_ADMIN_ROLE(), deployer);
        oracle.revokeRole(oracle.DEFAULT_ADMIN_ROLE(), deployer);

        // ItemFactory
        factory.grantRole(factory.DEFAULT_ADMIN_ROLE(), address(timelock));
        factory.grantRole(factory.FACTORY_ADMIN_ROLE(), address(timelock));
        factory.revokeRole(factory.FACTORY_ADMIN_ROLE(), deployer);
        factory.revokeRole(factory.DEFAULT_ADMIN_ROLE(), deployer);

        // LootBox
        lootBox.grantRole(lootBox.DEFAULT_ADMIN_ROLE(), address(timelock));
        lootBox.grantRole(lootBox.LOOT_ADMIN_ROLE(), address(timelock));
        lootBox.grantRole(lootBox.PAUSER_ROLE(), address(timelock));
        lootBox.revokeRole(lootBox.LOOT_ADMIN_ROLE(), deployer);
        lootBox.revokeRole(lootBox.PAUSER_ROLE(), deployer);
        lootBox.revokeRole(lootBox.DEFAULT_ADMIN_ROLE(), deployer);
        // Transfer the VRF-base ConfirmedOwner ownership to the Timelock. The Timelock must
        // submit a proposal calling `acceptOwnership()` to complete the handover. Until then
        // the deployer retains owner privileges *only* for `setCoordinator` — documented in
        // docs/AUDIT.md §4.
        lootBox.transferOwnership(address(timelock));

        // Timelock — drop deployer admin, keep self-administered.
        timelock.revokeRole(TIMELOCK_ADMIN, deployer);

        vm.stopBroadcast();

        _writeDeployment(d);
        _logDeployment(d);
    }

    function _logDeployment(Deployed memory d) internal pure {
        console2.log("GameToken      :", d.gameToken);
        console2.log("Timelock       :", d.timelock);
        console2.log("Governor       :", d.governor);
        console2.log("GameItemsProxy :", d.gameItemsProxy);
        console2.log("GameItemsImpl  :", d.gameItemsImpl);
        console2.log("ResourceA      :", d.resourceA);
        console2.log("ResourceB      :", d.resourceB);
        console2.log("ResourceAMM    :", d.amm);
        console2.log("YieldVault     :", d.yieldVault);
        console2.log("RentalVault    :", d.rentalVault);
        console2.log("LootBox        :", d.lootBox);
        console2.log("PriceOracle    :", d.priceOracle);
        console2.log("ItemFactory    :", d.itemFactory);
    }

    function _writeDeployment(Deployed memory d) internal {
        string memory chainId = vm.toString(block.chainid);
        string memory path = string.concat("./deployments/", chainId, ".json");
        string memory j = "deployment";
        vm.serializeAddress(j, "gameToken", d.gameToken);
        vm.serializeAddress(j, "timelock", d.timelock);
        vm.serializeAddress(j, "governor", d.governor);
        vm.serializeAddress(j, "gameItemsProxy", d.gameItemsProxy);
        vm.serializeAddress(j, "gameItemsImpl", d.gameItemsImpl);
        vm.serializeAddress(j, "resourceA", d.resourceA);
        vm.serializeAddress(j, "resourceB", d.resourceB);
        vm.serializeAddress(j, "amm", d.amm);
        vm.serializeAddress(j, "yieldVault", d.yieldVault);
        vm.serializeAddress(j, "rentalVault", d.rentalVault);
        vm.serializeAddress(j, "lootBox", d.lootBox);
        vm.serializeAddress(j, "priceOracle", d.priceOracle);
        string memory out = vm.serializeAddress(j, "itemFactory", d.itemFactory);
        vm.writeFile(path, out);
    }
}
