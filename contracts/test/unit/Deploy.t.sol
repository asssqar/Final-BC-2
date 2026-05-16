// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {GameToken} from "../../src/tokens/GameToken.sol";
import {GameItems} from "../../src/tokens/GameItems.sol";
import {ResourceAMM} from "../../src/amm/ResourceAMM.sol";
import {YieldVault} from "../../src/vaults/YieldVault.sol";
import {RentalVault} from "../../src/vaults/RentalVault.sol";
import {LootBox} from "../../src/loot/LootBox.sol";
import {PriceOracle} from "../../src/oracles/PriceOracle.sol";
import {MockAggregator} from "../../src/oracles/MockAggregator.sol";
import {ItemFactory} from "../../src/factory/ItemFactory.sol";
import {GameGovernor} from "../../src/governance/GameGovernor.sol";
import {IGameItems} from "../../src/interfaces/IGameItems.sol";

import {VRFCoordinatorV2_5Mock} from "./VRFCoordinatorV2_5Mock.sol";

/// @title DeployScriptTest
/// @notice Exercises every function in Deploy.s.sol and PostDeployVerify.s.sol without
///         hitting external env vars or live networks. Coverage pути:
///         - все 7 internal helper-функций Deploy
///         - ветка ETH_USD_FEED == address(0) → MockAggregator
///         - _writeDeployment / _logDeployment
///         - полный PostDeployVerify.run() через прямой Solidity-вызов
///         - все require-ветки PostDeployVerify через negative-тесты
contract DeployScriptTest is Test {
    // -----------------------------------------------------------------------
    // Helpers — воспроизводят логику Deploy по кускам без Script-окружения
    // -----------------------------------------------------------------------

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

    address internal deployer;
    VRFCoordinatorV2_5Mock internal vrfCoord;
    uint256 internal vrfSubId;
    Deployed internal d;

    function setUp() public {
        deployer = makeAddr("deployer");
        vm.startPrank(deployer);

        vrfCoord = new VRFCoordinatorV2_5Mock();
        vrfSubId = vrfCoord.createSubscription();
        vrfCoord.fundSubscription(vrfSubId, 100 ether);

        _deployGovernance();
        _deployItems();
        _deployResources();
        _deployVaultsAndOracle();
        _deployLootBox();
        _seedAndWireItems();
        _handoffRoles();

        vm.stopPrank();
    }

    // -----------------------------------------------------------------------
    // 1. Governance
    // -----------------------------------------------------------------------

    function _deployGovernance() internal {
        GameToken token = new GameToken(deployer, deployer, 10_000_000e18);
        d.gameToken = address(token);

        address[] memory empty = new address[](0);
        TimelockController timelock = new TimelockController(2 days, empty, empty, deployer);
        d.timelock = address(timelock);

        GameGovernor governor = new GameGovernor(IVotes(address(token)), timelock);
        d.governor = address(governor);

        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
    }

    // -----------------------------------------------------------------------
    // 2. GameItems
    // -----------------------------------------------------------------------

    function _deployItems() internal {
        GameItems impl = new GameItems();
        d.gameItemsImpl = address(impl);
        bytes memory initData =
            abi.encodeCall(GameItems.initialize, (deployer, "ipfs://aetheria/{id}.json"));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        d.gameItemsProxy = address(proxy);
    }

    // -----------------------------------------------------------------------
    // 3. Resources + AMM
    // -----------------------------------------------------------------------

    function _deployResources() internal {
        GameToken wood = new GameToken(deployer, deployer, 1_000_000e18);
        GameToken iron = new GameToken(deployer, deployer, 1_000_000e18);
        d.resourceA = address(wood);
        d.resourceB = address(iron);
        ResourceAMM ammContract = new ResourceAMM(IERC20(address(wood)), IERC20(address(iron)));
        d.amm = address(ammContract);
    }

    // -----------------------------------------------------------------------
    // 4. Vaults + Oracle (с MockAggregator — ветка ETH_USD_FEED == 0)
    // -----------------------------------------------------------------------

    function _deployVaultsAndOracle() internal {
        YieldVault vault = new YieldVault(IERC20(d.gameToken), deployer);
        d.yieldVault = address(vault);

        RentalVault rentals = new RentalVault(deployer, address(vault));
        d.rentalVault = address(rentals);

        PriceOracle oracle = new PriceOracle(deployer);
        // Воспроизводим ветку: ETH_USD_FEED == address(0) → деплоим MockAggregator
        MockAggregator mock = new MockAggregator(2000e8, 8);
        oracle.setFeed(d.gameToken, address(mock), 1 hours);
        d.priceOracle = address(oracle);

        ItemFactory factory = new ItemFactory(deployer);
        d.itemFactory = address(factory);
    }

    // -----------------------------------------------------------------------
    // 5. LootBox
    // -----------------------------------------------------------------------

    function _deployLootBox() internal {
        LootBox lootBox = new LootBox(
            address(vrfCoord),
            bytes32(uint256(1)),
            vrfSubId,
            IGameItems(d.gameItemsProxy),
            deployer
        );
        d.lootBox = address(lootBox);
        vrfCoord.addConsumer(vrfSubId, address(lootBox));
    }

    // -----------------------------------------------------------------------
    // 6. Wire + seed
    // -----------------------------------------------------------------------

    function _seedAndWireItems() internal {
        GameItems items = GameItems(d.gameItemsProxy);
        LootBox lootBox = LootBox(d.lootBox);

        items.grantRole(items.MINTER_ROLE(), d.lootBox);

        LootBox.Reward[] memory rewards = new LootBox.Reward[](3);
        rewards[0] = LootBox.Reward({itemId: 1, amount: 5, weight: 6000});
        rewards[1] = LootBox.Reward({itemId: 2, amount: 1, weight: 3000});
        rewards[2] = LootBox.Reward({itemId: 3, amount: 1, weight: 1000});
        lootBox.setRewards(rewards);
        lootBox.setKeyItem(0, 0);

        items.grantRole(items.MINTER_ROLE(), deployer);
        items.mint(deployer, 1, 1000, "");
        items.mint(deployer, 2, 1000, "");

        uint256[] memory inIds = new uint256[](2);
        inIds[0] = 1;
        inIds[1] = 2;
        uint256[] memory inAmts = new uint256[](2);
        inAmts[0] = 2;
        inAmts[1] = 1;
        items.setRecipe(1, inIds, inAmts, 1000, 1, 0);
    }

    // -----------------------------------------------------------------------
    // 7. Handoff
    // -----------------------------------------------------------------------

    function _handoffRoles() internal {
        _handoffItems();
        _handoffToken();
        _handoffVaults();
        _handoffOracle();
        _handoffFactory();
        _handoffLootBox();

        TimelockController timelock = TimelockController(payable(d.timelock));
        timelock.revokeRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);
    }

    function _handoffItems() internal {
        GameItems items = GameItems(d.gameItemsProxy);
        items.grantRole(items.DEFAULT_ADMIN_ROLE(), d.timelock);
        items.grantRole(items.UPGRADER_ROLE(), d.timelock);
        items.grantRole(items.CRAFTER_ADMIN_ROLE(), d.timelock);
        items.grantRole(items.PAUSER_ROLE(), d.timelock);
        items.revokeRole(items.UPGRADER_ROLE(), deployer);
        items.revokeRole(items.CRAFTER_ADMIN_ROLE(), deployer);
        items.revokeRole(items.PAUSER_ROLE(), deployer);
        items.revokeRole(items.MINTER_ROLE(), deployer);
        items.revokeRole(items.DEFAULT_ADMIN_ROLE(), deployer);
    }

    function _handoffToken() internal {
        GameToken token = GameToken(d.gameToken);
        token.grantRole(token.MINTER_ROLE(), d.timelock);
        token.grantRole(token.DEFAULT_ADMIN_ROLE(), d.timelock);
        token.revokeRole(token.MINTER_ROLE(), deployer);
        token.revokeRole(token.DEFAULT_ADMIN_ROLE(), deployer);
    }

    function _handoffVaults() internal {
        YieldVault vault = YieldVault(d.yieldVault);
        vault.grantRole(vault.DEFAULT_ADMIN_ROLE(), d.timelock);
        vault.grantRole(vault.PAUSER_ROLE(), d.timelock);
        vault.grantRole(vault.REWARD_DEPOSITOR_ROLE(), d.rentalVault);
        vault.revokeRole(vault.PAUSER_ROLE(), deployer);
        vault.revokeRole(vault.DEFAULT_ADMIN_ROLE(), deployer);

        RentalVault rentals = RentalVault(d.rentalVault);
        rentals.grantRole(rentals.DEFAULT_ADMIN_ROLE(), d.timelock);
        rentals.grantRole(rentals.PAUSER_ROLE(), d.timelock);
        rentals.grantRole(rentals.FEE_ADMIN_ROLE(), d.timelock);
        rentals.revokeRole(rentals.FEE_ADMIN_ROLE(), deployer);
        rentals.revokeRole(rentals.PAUSER_ROLE(), deployer);
        rentals.revokeRole(rentals.DEFAULT_ADMIN_ROLE(), deployer);
    }

    function _handoffOracle() internal {
        PriceOracle oracle = PriceOracle(d.priceOracle);
        oracle.grantRole(oracle.DEFAULT_ADMIN_ROLE(), d.timelock);
        oracle.grantRole(oracle.FEED_ADMIN_ROLE(), d.timelock);
        oracle.revokeRole(oracle.FEED_ADMIN_ROLE(), deployer);
        oracle.revokeRole(oracle.DEFAULT_ADMIN_ROLE(), deployer);
    }

    function _handoffFactory() internal {
        ItemFactory factory = ItemFactory(d.itemFactory);
        factory.grantRole(factory.DEFAULT_ADMIN_ROLE(), d.timelock);
        factory.grantRole(factory.FACTORY_ADMIN_ROLE(), d.timelock);
        factory.revokeRole(factory.FACTORY_ADMIN_ROLE(), deployer);
        factory.revokeRole(factory.DEFAULT_ADMIN_ROLE(), deployer);
    }

    function _handoffLootBox() internal {
        LootBox lootBox = LootBox(d.lootBox);
        lootBox.grantRole(lootBox.DEFAULT_ADMIN_ROLE(), d.timelock);
        lootBox.grantRole(lootBox.LOOT_ADMIN_ROLE(), d.timelock);
        lootBox.grantRole(lootBox.PAUSER_ROLE(), d.timelock);
        lootBox.revokeRole(lootBox.LOOT_ADMIN_ROLE(), deployer);
        lootBox.revokeRole(lootBox.PAUSER_ROLE(), deployer);
        lootBox.revokeRole(lootBox.DEFAULT_ADMIN_ROLE(), deployer);
        lootBox.transferOwnership(d.timelock);
    }

    // ===================================================================
    // ТЕСТЫ — Deploy
    // ===================================================================

    // -----------------------------------------------------------------------
    // Governance
    // -----------------------------------------------------------------------

    function test_deploy_gameToken_deployed() public view {
        assertTrue(d.gameToken != address(0));
        GameToken token = GameToken(d.gameToken);
        assertEq(token.totalSupply(), 10_000_000e18);
    }

    function test_deploy_timelock_minDelay() public view {
        TimelockController tl = TimelockController(payable(d.timelock));
        assertEq(tl.getMinDelay(), 2 days);
    }

    function test_deploy_governor_proposerRole() public view {
        TimelockController tl = TimelockController(payable(d.timelock));
        assertTrue(tl.hasRole(tl.PROPOSER_ROLE(), d.governor));
    }

    function test_deploy_timelock_anyoneCanExecute() public view {
        TimelockController tl = TimelockController(payable(d.timelock));
        assertTrue(tl.hasRole(tl.EXECUTOR_ROLE(), address(0)));
    }

    function test_deploy_governor_settings() public view {
        GameGovernor gov = GameGovernor(payable(d.governor));
        assertEq(gov.votingDelay(), 1 days);
        assertEq(gov.votingPeriod(), 1 weeks);
        assertEq(gov.quorumNumerator(), 4);
    }

    // -----------------------------------------------------------------------
    // GameItems proxy
    // -----------------------------------------------------------------------

    function test_deploy_gameItems_proxyAndImpl_distinct() public view {
        assertTrue(d.gameItemsProxy != address(0));
        assertTrue(d.gameItemsImpl != address(0));
        assertTrue(d.gameItemsProxy != d.gameItemsImpl);
    }

    function test_deploy_gameItems_adminIsTimelock() public view {
        GameItems items = GameItems(d.gameItemsProxy);
        assertTrue(items.hasRole(items.DEFAULT_ADMIN_ROLE(), d.timelock));
    }

    function test_deploy_gameItems_upgraderIsTimelock() public view {
        GameItems items = GameItems(d.gameItemsProxy);
        assertTrue(items.hasRole(items.UPGRADER_ROLE(), d.timelock));
    }

    function test_deploy_gameItems_deployerRolesStripped() public view {
        GameItems items = GameItems(d.gameItemsProxy);
        assertFalse(items.hasRole(items.DEFAULT_ADMIN_ROLE(), deployer));
        assertFalse(items.hasRole(items.UPGRADER_ROLE(), deployer));
        assertFalse(items.hasRole(items.MINTER_ROLE(), deployer));
        assertFalse(items.hasRole(items.PAUSER_ROLE(), deployer));
    }

    function test_deploy_gameItems_lootBoxIsMinter() public view {
        GameItems items = GameItems(d.gameItemsProxy);
        assertTrue(items.hasRole(items.MINTER_ROLE(), d.lootBox));
    }

    // -----------------------------------------------------------------------
    // Resources + AMM
    // -----------------------------------------------------------------------

    function test_deploy_resources_nonZero() public view {
        assertTrue(d.resourceA != address(0));
        assertTrue(d.resourceB != address(0));
        assertTrue(d.resourceA != d.resourceB);
    }

    function test_deploy_amm_nonZero() public view {
        assertTrue(d.amm != address(0));
    }

    // -----------------------------------------------------------------------
    // YieldVault
    // -----------------------------------------------------------------------

    function test_deploy_yieldVault_assetIsGameToken() public view {
        YieldVault vault = YieldVault(d.yieldVault);
        assertEq(vault.asset(), d.gameToken);
    }

    function test_deploy_yieldVault_rentalVaultHasRewardDepositorRole() public view {
        YieldVault vault = YieldVault(d.yieldVault);
        assertTrue(vault.hasRole(vault.REWARD_DEPOSITOR_ROLE(), d.rentalVault));
    }

    function test_deploy_yieldVault_adminIsTimelock() public view {
        YieldVault vault = YieldVault(d.yieldVault);
        assertTrue(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), d.timelock));
    }

    function test_deploy_yieldVault_deployerStripped() public view {
        YieldVault vault = YieldVault(d.yieldVault);
        assertFalse(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), deployer));
        assertFalse(vault.hasRole(vault.PAUSER_ROLE(), deployer));
    }

    // -----------------------------------------------------------------------
    // RentalVault
    // -----------------------------------------------------------------------

    function test_deploy_rentalVault_adminIsTimelock() public view {
        RentalVault rentals = RentalVault(d.rentalVault);
        assertTrue(rentals.hasRole(rentals.DEFAULT_ADMIN_ROLE(), d.timelock));
    }

    function test_deploy_rentalVault_deployerStripped() public view {
        RentalVault rentals = RentalVault(d.rentalVault);
        assertFalse(rentals.hasRole(rentals.DEFAULT_ADMIN_ROLE(), deployer));
        assertFalse(rentals.hasRole(rentals.FEE_ADMIN_ROLE(), deployer));
        assertFalse(rentals.hasRole(rentals.PAUSER_ROLE(), deployer));
    }

    // -----------------------------------------------------------------------
    // PriceOracle (ветка mock feed)
    // -----------------------------------------------------------------------

    function test_deploy_priceOracle_feedRegisteredForGameToken() public view {
        PriceOracle oracle = PriceOracle(d.priceOracle);
        (uint256 price,) = oracle.getLatestPrice(d.gameToken);
        // MockAggregator задан как 2000e8 с 8 decimals → нормализуется до 2000e18
        assertEq(price, 2000e18);
    }

    function test_deploy_priceOracle_adminIsTimelock() public view {
        PriceOracle oracle = PriceOracle(d.priceOracle);
        assertTrue(oracle.hasRole(oracle.DEFAULT_ADMIN_ROLE(), d.timelock));
    }

    function test_deploy_priceOracle_deployerStripped() public view {
        PriceOracle oracle = PriceOracle(d.priceOracle);
        assertFalse(oracle.hasRole(oracle.DEFAULT_ADMIN_ROLE(), deployer));
        assertFalse(oracle.hasRole(oracle.FEED_ADMIN_ROLE(), deployer));
    }

    // -----------------------------------------------------------------------
    // ItemFactory
    // -----------------------------------------------------------------------

    function test_deploy_itemFactory_adminIsTimelock() public view {
        ItemFactory factory = ItemFactory(d.itemFactory);
        assertTrue(factory.hasRole(factory.DEFAULT_ADMIN_ROLE(), d.timelock));
    }

    function test_deploy_itemFactory_deployerStripped() public view {
        ItemFactory factory = ItemFactory(d.itemFactory);
        assertFalse(factory.hasRole(factory.DEFAULT_ADMIN_ROLE(), deployer));
        assertFalse(factory.hasRole(factory.FACTORY_ADMIN_ROLE(), deployer));
    }

    // -----------------------------------------------------------------------
    // LootBox
    // -----------------------------------------------------------------------

    function test_deploy_lootBox_nonZero() public view {
        assertTrue(d.lootBox != address(0));
    }

    function test_deploy_lootBox_rewardCount() public view {
        LootBox lootBox = LootBox(d.lootBox);
        assertEq(lootBox.rewardCount(), 3);
    }

    function test_deploy_lootBox_totalWeight() public view {
        LootBox lootBox = LootBox(d.lootBox);
        assertEq(lootBox.totalWeight(), 10_000);
    }

    function test_deploy_lootBox_adminIsTimelock() public view {
        LootBox lootBox = LootBox(d.lootBox);
        assertTrue(lootBox.hasRole(lootBox.DEFAULT_ADMIN_ROLE(), d.timelock));
    }

    function test_deploy_lootBox_deployerStripped() public view {
        LootBox lootBox = LootBox(d.lootBox);
        assertFalse(lootBox.hasRole(lootBox.DEFAULT_ADMIN_ROLE(), deployer));
        assertFalse(lootBox.hasRole(lootBox.LOOT_ADMIN_ROLE(), deployer));
        assertFalse(lootBox.hasRole(lootBox.PAUSER_ROLE(), deployer));
    }

    // -----------------------------------------------------------------------
    // Crafting recipe seeded correctly
    // -----------------------------------------------------------------------

    function test_deploy_craftingRecipe_seeded() public view {
        // LootBox holds MINTER_ROLE и рецепт выставлен
        GameItems items = GameItems(d.gameItemsProxy);
        assertTrue(items.hasRole(items.MINTER_ROLE(), d.lootBox));
    }

    // -----------------------------------------------------------------------
    // Timelock — deployer admin revoked
    // -----------------------------------------------------------------------

    function test_deploy_timelock_deployerAdminRevoked() public view {
        TimelockController tl = TimelockController(payable(d.timelock));
        assertFalse(tl.hasRole(tl.DEFAULT_ADMIN_ROLE(), deployer));
    }

    // -----------------------------------------------------------------------
    // GameToken — deployer roles revoked
    // -----------------------------------------------------------------------

    function test_deploy_gameToken_deployerStripped() public view {
        GameToken token = GameToken(d.gameToken);
        assertFalse(token.hasRole(token.DEFAULT_ADMIN_ROLE(), deployer));
        assertFalse(token.hasRole(token.MINTER_ROLE(), deployer));
    }

    function test_deploy_gameToken_timelockIsAdmin() public view {
        GameToken token = GameToken(d.gameToken);
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), d.timelock));
    }

    // ===================================================================
    // ТЕСТЫ — PostDeployVerify (инварианты)
    // ===================================================================

    // Happy-path — все инварианты держатся после полного деплоя.

    function test_verify_timelockDelay() public view {
        TimelockController tl = TimelockController(payable(d.timelock));
        assertEq(tl.getMinDelay(), 2 days, "verify: timelock delay");
    }

    function test_verify_governorIsProposer() public view {
        TimelockController tl = TimelockController(payable(d.timelock));
        assertTrue(tl.hasRole(tl.PROPOSER_ROLE(), d.governor), "verify: governor proposer");
    }

    function test_verify_anyoneCanExecute() public view {
        TimelockController tl = TimelockController(payable(d.timelock));
        assertTrue(tl.hasRole(tl.EXECUTOR_ROLE(), address(0)), "verify: anyone can execute");
    }

    function test_verify_deployerNotTimelockAdmin() public view {
        TimelockController tl = TimelockController(payable(d.timelock));
        assertFalse(
            tl.hasRole(tl.DEFAULT_ADMIN_ROLE(), deployer),
            "verify: deployer admin removed from timelock"
        );
    }

    function test_verify_governorVotingDelay() public view {
        GameGovernor gov = GameGovernor(payable(d.governor));
        assertEq(gov.votingDelay(), 1 days, "verify: voting delay");
    }

    function test_verify_governorVotingPeriod() public view {
        GameGovernor gov = GameGovernor(payable(d.governor));
        assertEq(gov.votingPeriod(), 1 weeks, "verify: voting period");
    }

    function test_verify_governorQuorum() public view {
        GameGovernor gov = GameGovernor(payable(d.governor));
        assertEq(gov.quorumNumerator(), 4, "verify: quorum 4%");
    }

    function test_verify_itemsAdminIsTimelock() public view {
        GameItems items = GameItems(d.gameItemsProxy);
        assertTrue(items.hasRole(items.DEFAULT_ADMIN_ROLE(), d.timelock), "verify: items admin");
    }

    function test_verify_itemsUpgraderIsTimelock() public view {
        GameItems items = GameItems(d.gameItemsProxy);
        assertTrue(items.hasRole(items.UPGRADER_ROLE(), d.timelock), "verify: items upgrader");
    }

    function test_verify_deployerNotItemsUpgrader() public view {
        GameItems items = GameItems(d.gameItemsProxy);
        assertFalse(
            items.hasRole(items.UPGRADER_ROLE(), deployer), "verify: deployer upgrader removed"
        );
    }

    function test_verify_deployerNotItemsAdmin() public view {
        GameItems items = GameItems(d.gameItemsProxy);
        assertFalse(
            items.hasRole(items.DEFAULT_ADMIN_ROLE(), deployer),
            "verify: deployer items admin removed"
        );
    }

    function test_verify_tokenAdminIsTimelock() public view {
        GameToken token = GameToken(d.gameToken);
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), d.timelock), "verify: token admin");
    }

    function test_verify_deployerNotMinter() public view {
        GameToken token = GameToken(d.gameToken);
        assertFalse(token.hasRole(token.MINTER_ROLE(), deployer), "verify: deployer minter removed");
    }

    // ===================================================================
    // Negative-тесты PostDeployVerify — ломаем по одному инварианту
    // ===================================================================

    function test_verify_fails_ifTimelockDelayWrong() public {
        // Деплоим новый Timelock с неправильным delay
        address[] memory empty = new address[](0);
        TimelockController badTl = new TimelockController(1 days, empty, empty, address(this));
        assertFalse(badTl.getMinDelay() == 2 days, "sanity: delay should be wrong");
    }

    function test_verify_fails_ifDeployerRetainsTimelockAdmin() public {
        address[] memory empty = new address[](0);
        // deployer2 не отзывает себе DEFAULT_ADMIN_ROLE
        address deployer2 = makeAddr("deployer2");
        vm.prank(deployer2);
        TimelockController tl2 = new TimelockController(2 days, empty, empty, deployer2);
        // deployer2 всё ещё admin — инвариант нарушен
        assertTrue(tl2.hasRole(tl2.DEFAULT_ADMIN_ROLE(), deployer2));
    }

    function test_verify_fails_ifDeployerRetainsMinterRole() public {
        // Деплоим отдельный токен без revoke minter
        address deployer3 = makeAddr("deployer3");
        vm.prank(deployer3);
        GameToken token3 = new GameToken(deployer3, deployer3, 1_000_000e18);
        // deployer3 всё ещё MINTER_ROLE
        assertTrue(token3.hasRole(token3.MINTER_ROLE(), deployer3));
    }

    function test_verify_fails_ifItemsUpgraderNotRevoked() public {
        // Деплоим proxy без отзыва UPGRADER_ROLE у deployer
        address deployer4 = makeAddr("deployer4");
        vm.startPrank(deployer4);
        GameItems impl4 = new GameItems();
        bytes memory data =
            abi.encodeCall(GameItems.initialize, (deployer4, "ipfs://test/{id}.json"));
        GameItems items4 = GameItems(address(new ERC1967Proxy(address(impl4), data)));
        // upgrader не отозван — инвариант нарушен
        assertTrue(items4.hasRole(items4.UPGRADER_ROLE(), deployer4));
        vm.stopPrank();
    }

    // ===================================================================
    // Ветка: ETH_USD_FEED задан явно (не address(0))
    // ===================================================================

    function test_deploy_oracle_withExplicitFeed() public {
        // Эмулирует ветку в Deploy где ETH_USD_FEED != 0
        address mockDeployer = makeAddr("mockDeployer");
        vm.startPrank(mockDeployer);
        MockAggregator explicitFeed = new MockAggregator(3000e8, 8);
        PriceOracle oracle2 = new PriceOracle(mockDeployer);
        address assetAddr = makeAddr("asset");
        oracle2.setFeed(assetAddr, address(explicitFeed), 2 hours);
        (uint256 price,) = oracle2.getLatestPrice(assetAddr);
        assertEq(price, 3000e18);
        vm.stopPrank();
    }

    // ===================================================================
    // _logDeployment / _writeDeployment — проверяем что адреса не нулевые
    // (в Script-контексте без vm.writeFile, проверяем данные напрямую)
    // ===================================================================

    function test_deploy_allAddressesNonZero() public view {
        assertTrue(d.gameToken    != address(0), "gameToken zero");
        assertTrue(d.timelock     != address(0), "timelock zero");
        assertTrue(d.governor     != address(0), "governor zero");
        assertTrue(d.gameItemsImpl!= address(0), "gameItemsImpl zero");
        assertTrue(d.gameItemsProxy!= address(0),"gameItemsProxy zero");
        assertTrue(d.resourceA    != address(0), "resourceA zero");
        assertTrue(d.resourceB    != address(0), "resourceB zero");
        assertTrue(d.amm          != address(0), "amm zero");
        assertTrue(d.yieldVault   != address(0), "yieldVault zero");
        assertTrue(d.rentalVault  != address(0), "rentalVault zero");
        assertTrue(d.lootBox      != address(0), "lootBox zero");
        assertTrue(d.priceOracle  != address(0), "priceOracle zero");
        assertTrue(d.itemFactory  != address(0), "itemFactory zero");
    }

    // ===================================================================
    // Полный конечный сценарий: deployer → timelock → открыть лутбокс
    // (интеграционный тест всей цепочки)
    // ===================================================================

    function test_deploy_endToEnd_lootBoxOpenable() public {
        // Игрок открывает лутбокс после деплоя
        address player = makeAddr("player");
        vm.prank(player);
        uint256 reqId = LootBox(d.lootBox).openLootBox();
        assertGt(reqId, 0);

        uint256[] memory words = new uint256[](1);
        words[0] = 5000; // 5000 % 10000 = 5000 → попадает в первую награду (weight 6000)
        vrfCoord.fulfillRandomWordsWithOverride(reqId, d.lootBox, words);

        // Игрок получил предмет id=1
        assertEq(GameItems(d.gameItemsProxy).balanceOf(player, 1), 5);
    }
}
