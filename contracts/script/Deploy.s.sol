// // SPDX-License-Identifier: MIT
// pragma solidity 0.8.24;

// import {Script, console2} from "forge-std/Script.sol";
// import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
// import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
// import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

// import {GameToken} from "../src/tokens/GameToken.sol";
// import {GameItems} from "../src/tokens/GameItems.sol";
// import {ResourceAMM} from "../src/amm/ResourceAMM.sol";
// import {YieldVault} from "../src/vaults/YieldVault.sol";
// import {RentalVault} from "../src/vaults/RentalVault.sol";
// import {LootBox} from "../src/loot/LootBox.sol";
// import {PriceOracle} from "../src/oracles/PriceOracle.sol";
// import {MockAggregator} from "../src/oracles/MockAggregator.sol";
// import {ItemFactory} from "../src/factory/ItemFactory.sol";
// import {GameGovernor} from "../src/governance/GameGovernor.sol";

// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import {IGameItems} from "../src/interfaces/IGameItems.sol";

// /// @title Deploy
// /// @notice Idempotent, parameterised deployment script. Outputs addresses to
// ///         `deployments/<chainId>.json` for the frontend & subgraph.
// ///
// /// Required env vars:
// ///   DEPLOYER_PRIVATE_KEY         - deployer's private key (broadcast)
// ///   VRF_COORDINATOR              - Chainlink VRF v2.5 coordinator on the target chain
// ///   VRF_KEY_HASH                 - VRF key hash
// ///   VRF_SUBSCRIPTION_ID          - subscription id (uint256)
// ///   ETH_USD_FEED                 - Chainlink price feed address (or 0x0 → deploy mock)
// ///
// /// Usage:
// ///   forge script script/Deploy.s.sol --rpc-url $ARB_SEPOLIA_RPC --broadcast --verify
// contract Deploy is Script {
//     struct Deployed {
//         address gameToken;
//         address timelock;
//         address governor;
//         address gameItemsImpl;
//         address gameItemsProxy;
//         address resourceA;
//         address resourceB;
//         address amm;
//         address yieldVault;
//         address rentalVault;
//         address lootBox;
//         address priceOracle;
//         address itemFactory;
//     }

//     function run() external returns (Deployed memory d) {
//         uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
//         address deployer = vm.addr(pk);
//         vm.startBroadcast(pk);

//         _deployGovernance(d, deployer);
//         _deployItems(d, deployer);
//         _deployResources(d, deployer);
//         _deployVaultsAndOracle(d, deployer);
//         _deployLootBox(d, deployer);
//         _seedAndWireItems(d, deployer);
//         _handoffRoles(d, deployer);

//         vm.stopBroadcast();

//         _writeDeployment(d);
//         _logDeployment(d);
//     }

//     // -------------------------------------------------------------------
//     // 1. Governance token + Timelock + Governor
//     // -------------------------------------------------------------------
//     function _deployGovernance(Deployed memory d, address deployer) internal {
//         GameToken token = new GameToken(deployer, deployer, 10_000_000e18);
//         d.gameToken = address(token);

//         address[] memory empty = new address[](0);
//         TimelockController timelock = new TimelockController(2 days, empty, empty, deployer);
//         d.timelock = address(timelock);

//         GameGovernor governor = new GameGovernor(IVotes(address(token)), timelock);
//         d.governor = address(governor);

//         timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
//         timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0));
//         timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
//     }

//     // -------------------------------------------------------------------
//     // 2. GameItems (UUPS proxy)
//     // -------------------------------------------------------------------
//     function _deployItems(Deployed memory d, address deployer) internal {
//         GameItems impl = new GameItems();
//         d.gameItemsImpl = address(impl);
//         bytes memory initData =
//             abi.encodeCall(GameItems.initialize, (deployer, "ipfs://aetheria/{id}.json"));
//         ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
//         d.gameItemsProxy = address(proxy);
//     }

//     // -------------------------------------------------------------------
//     // 3. Two ERC-20 resources + AMM
//     // -------------------------------------------------------------------
//     function _deployResources(Deployed memory d, address deployer) internal {
//         GameToken wood = new GameToken(deployer, deployer, 1_000_000e18);
//         GameToken iron = new GameToken(deployer, deployer, 1_000_000e18);
//         d.resourceA = address(wood);
//         d.resourceB = address(iron);

//         ResourceAMM amm = new ResourceAMM(IERC20(address(wood)), IERC20(address(iron)));
//         d.amm = address(amm);
//     }

//     // -------------------------------------------------------------------
//     // 4. YieldVault, RentalVault, PriceOracle, ItemFactory
//     // -------------------------------------------------------------------
//     function _deployVaultsAndOracle(Deployed memory d, address deployer) internal {
//         YieldVault vault = new YieldVault(IERC20(d.gameToken), deployer);
//         d.yieldVault = address(vault);

//         RentalVault rentals = new RentalVault(deployer, address(vault));
//         d.rentalVault = address(rentals);

//         PriceOracle oracle = new PriceOracle(deployer);
//         address ethUsdFeed = vm.envOr("ETH_USD_FEED", address(0));
//         if (ethUsdFeed == address(0)) {
//             MockAggregator mock = new MockAggregator(2000e8, 8); // $2,000
//             ethUsdFeed = address(mock);
//         }
//         oracle.setFeed(d.gameToken, ethUsdFeed, 1 hours);
//         d.priceOracle = address(oracle);

//         ItemFactory factory = new ItemFactory(deployer);
//         d.itemFactory = address(factory);
//     }

//     // -------------------------------------------------------------------
//     // 5. LootBox (Chainlink VRF v2.5)
//     // -------------------------------------------------------------------
//     function _deployLootBox(Deployed memory d, address deployer) internal {
//         address vrfCoord = vm.envAddress("VRF_COORDINATOR");
//         bytes32 keyHash = vm.envBytes32("VRF_KEY_HASH");
//         uint256 subId = vm.envUint("VRF_SUBSCRIPTION_ID");
//         LootBox lootBox =
//             new LootBox(vrfCoord, keyHash, subId, IGameItems(d.gameItemsProxy), deployer);
//         d.lootBox = address(lootBox);
//     }

//     // -------------------------------------------------------------------
//     // 6. Wire LootBox into GameItems + seed crafting recipe
//     // -------------------------------------------------------------------
//     function _seedAndWireItems(Deployed memory d, address deployer) internal {
//         GameItems items = GameItems(d.gameItemsProxy);
//         LootBox lootBox = LootBox(d.lootBox);

//         items.grantRole(items.MINTER_ROLE(), d.lootBox);

//         LootBox.Reward[] memory rewards = new LootBox.Reward[](3);
//         rewards[0] = LootBox.Reward({itemId: 1, amount: 5, weight: 6000}); // 60% common
//         rewards[1] = LootBox.Reward({itemId: 2, amount: 1, weight: 3000}); // 30% rare
//         rewards[2] = LootBox.Reward({itemId: 3, amount: 1, weight: 1000}); // 10% epic
//         lootBox.setRewards(rewards);
//         lootBox.setKeyItem(0, 0);

//         // One-time seed mints for the crafting recipe (2 wood + 1 iron → 1 sword).
//         items.grantRole(items.MINTER_ROLE(), deployer);
//         items.mint(deployer, 1, 1000, "");
//         items.mint(deployer, 2, 1000, "");

//         uint256[] memory inIds = new uint256[](2);
//         inIds[0] = 1;
//         inIds[1] = 2;
//         uint256[] memory inAmts = new uint256[](2);
//         inAmts[0] = 2;
//         inAmts[1] = 1;
//         items.setRecipe(1, inIds, inAmts, 1000, 1, 0);
//     }

//     // -------------------------------------------------------------------
//     // 7. Hand off all admin powers to the Timelock
//     // -------------------------------------------------------------------
//     function _handoffRoles(Deployed memory d, address deployer) internal {
//         _handoffItems(d, deployer);
//         _handoffToken(d, deployer);
//         _handoffVaults(d, deployer);
//         _handoffOracle(d, deployer);
//         _handoffFactory(d, deployer);
//         _handoffLootBox(d, deployer);

//         // Timelock — drop deployer admin, keep self-administered.
//         TimelockController timelock = TimelockController(payable(d.timelock));
//         timelock.revokeRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);
//     }

//     function _handoffItems(Deployed memory d, address deployer) internal {
//         GameItems items = GameItems(d.gameItemsProxy);
//         items.grantRole(items.DEFAULT_ADMIN_ROLE(), d.timelock);
//         items.grantRole(items.UPGRADER_ROLE(), d.timelock);
//         items.grantRole(items.CRAFTER_ADMIN_ROLE(), d.timelock);
//         items.grantRole(items.PAUSER_ROLE(), d.timelock);
//         items.revokeRole(items.UPGRADER_ROLE(), deployer);
//         items.revokeRole(items.CRAFTER_ADMIN_ROLE(), deployer);
//         items.revokeRole(items.PAUSER_ROLE(), deployer);
//         items.revokeRole(items.MINTER_ROLE(), deployer);
//         items.revokeRole(items.DEFAULT_ADMIN_ROLE(), deployer);
//     }

//     function _handoffToken(Deployed memory d, address deployer) internal {
//         GameToken token = GameToken(d.gameToken);
//         token.grantRole(token.MINTER_ROLE(), d.timelock);
//         token.grantRole(token.DEFAULT_ADMIN_ROLE(), d.timelock);
//         token.revokeRole(token.MINTER_ROLE(), deployer);
//         token.revokeRole(token.DEFAULT_ADMIN_ROLE(), deployer);
//     }

//     function _handoffVaults(Deployed memory d, address deployer) internal {
//         YieldVault vault = YieldVault(d.yieldVault);
//         vault.grantRole(vault.DEFAULT_ADMIN_ROLE(), d.timelock);
//         vault.grantRole(vault.PAUSER_ROLE(), d.timelock);
//         vault.grantRole(vault.REWARD_DEPOSITOR_ROLE(), d.rentalVault);
//         vault.revokeRole(vault.PAUSER_ROLE(), deployer);
//         vault.revokeRole(vault.DEFAULT_ADMIN_ROLE(), deployer);

//         RentalVault rentals = RentalVault(d.rentalVault);
//         rentals.grantRole(rentals.DEFAULT_ADMIN_ROLE(), d.timelock);
//         rentals.grantRole(rentals.PAUSER_ROLE(), d.timelock);
//         rentals.grantRole(rentals.FEE_ADMIN_ROLE(), d.timelock);
//         rentals.revokeRole(rentals.FEE_ADMIN_ROLE(), deployer);
//         rentals.revokeRole(rentals.PAUSER_ROLE(), deployer);
//         rentals.revokeRole(rentals.DEFAULT_ADMIN_ROLE(), deployer);
//     }

//     function _handoffOracle(Deployed memory d, address deployer) internal {
//         PriceOracle oracle = PriceOracle(d.priceOracle);
//         oracle.grantRole(oracle.DEFAULT_ADMIN_ROLE(), d.timelock);
//         oracle.grantRole(oracle.FEED_ADMIN_ROLE(), d.timelock);
//         oracle.revokeRole(oracle.FEED_ADMIN_ROLE(), deployer);
//         oracle.revokeRole(oracle.DEFAULT_ADMIN_ROLE(), deployer);
//     }

//     function _handoffFactory(Deployed memory d, address deployer) internal {
//         ItemFactory factory = ItemFactory(d.itemFactory);
//         factory.grantRole(factory.DEFAULT_ADMIN_ROLE(), d.timelock);
//         factory.grantRole(factory.FACTORY_ADMIN_ROLE(), d.timelock);
//         factory.revokeRole(factory.FACTORY_ADMIN_ROLE(), deployer);
//         factory.revokeRole(factory.DEFAULT_ADMIN_ROLE(), deployer);
//     }

//     function _handoffLootBox(Deployed memory d, address deployer) internal {
//         LootBox lootBox = LootBox(d.lootBox);
//         lootBox.grantRole(lootBox.DEFAULT_ADMIN_ROLE(), d.timelock);
//         lootBox.grantRole(lootBox.LOOT_ADMIN_ROLE(), d.timelock);
//         lootBox.grantRole(lootBox.PAUSER_ROLE(), d.timelock);
//         lootBox.revokeRole(lootBox.LOOT_ADMIN_ROLE(), deployer);
//         lootBox.revokeRole(lootBox.PAUSER_ROLE(), deployer);
//         lootBox.revokeRole(lootBox.DEFAULT_ADMIN_ROLE(), deployer);
//         // Transfer the VRF-base ConfirmedOwner ownership to the Timelock. The Timelock must
//         // submit a proposal calling `acceptOwnership()` to complete the handover. Until then
//         // the deployer retains owner privileges *only* for `setCoordinator` — documented in
//         // docs/AUDIT.md §4.
//         lootBox.transferOwnership(d.timelock);
//     }

//     // -------------------------------------------------------------------
//     // Logging & output
//     // -------------------------------------------------------------------
//     function _logDeployment(Deployed memory d) internal pure {
//         console2.log("GameToken      :", d.gameToken);
//         console2.log("Timelock       :", d.timelock);
//         console2.log("Governor       :", d.governor);
//         console2.log("GameItemsProxy :", d.gameItemsProxy);
//         console2.log("GameItemsImpl  :", d.gameItemsImpl);
//         console2.log("ResourceA      :", d.resourceA);
//         console2.log("ResourceB      :", d.resourceB);
//         console2.log("ResourceAMM    :", d.amm);
//         console2.log("YieldVault     :", d.yieldVault);
//         console2.log("RentalVault    :", d.rentalVault);
//         console2.log("LootBox        :", d.lootBox);
//         console2.log("PriceOracle    :", d.priceOracle);
//         console2.log("ItemFactory    :", d.itemFactory);
//     }

//     function _writeDeployment(Deployed memory d) internal {
//         string memory chainId = vm.toString(block.chainid);
//         string memory path = string.concat("./deployments/", chainId, ".json");
//         string memory j = "deployment";
//         vm.serializeAddress(j, "gameToken", d.gameToken);
//         vm.serializeAddress(j, "timelock", d.timelock);
//         vm.serializeAddress(j, "governor", d.governor);
//         vm.serializeAddress(j, "gameItemsProxy", d.gameItemsProxy);
//         vm.serializeAddress(j, "gameItemsImpl", d.gameItemsImpl);
//         vm.serializeAddress(j, "resourceA", d.resourceA);
//         vm.serializeAddress(j, "resourceB", d.resourceB);
//         vm.serializeAddress(j, "amm", d.amm);
//         vm.serializeAddress(j, "yieldVault", d.yieldVault);
//         vm.serializeAddress(j, "rentalVault", d.rentalVault);
//         vm.serializeAddress(j, "lootBox", d.lootBox);
//         vm.serializeAddress(j, "priceOracle", d.priceOracle);
//         string memory out = vm.serializeAddress(j, "itemFactory", d.itemFactory);
//         vm.writeFile(path, out);
//     }
// }
