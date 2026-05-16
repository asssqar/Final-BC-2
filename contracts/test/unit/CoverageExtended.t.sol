// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {GameItems} from "../../src/tokens/GameItems.sol";
import {GameToken} from "../../src/tokens/GameToken.sol";
import {RentalVault} from "../../src/vaults/RentalVault.sol";
import {PriceOracle} from "../../src/oracles/PriceOracle.sol";
import {MockAggregator} from "../../src/oracles/MockAggregator.sol";
import {LootBox} from "../../src/loot/LootBox.sol";
import {IGameItems} from "../../src/interfaces/IGameItems.sol";
import {VRFCoordinatorV2_5Mock} from "./VRFCoordinatorV2_5Mock.sol";

// ============================================================
// Tiny PureMath wrapper (library нельзя вызвать напрямую)
// ============================================================
import {PureMath} from "../../src/libs/PureMath.sol";

contract PureMathWrapper {
    function sqrt(uint256 x) external pure returns (uint256) { return PureMath.sqrt(x); }
    function mulDiv(uint256 a, uint256 b, uint256 d) external pure returns (uint256) { return PureMath.mulDiv(a, b, d); }
    function min(uint256 a, uint256 b) external pure returns (uint256) { return PureMath.min(a, b); }
}

// ============================================================
// RentalVault — extended branch coverage
// ============================================================

contract RentalVaultExtendedTest is Test {
    GameItems internal items;
    GameToken internal token;
    RentalVault internal rental;
    address internal admin   = address(this);
    address internal owner   = address(0xAA);
    address internal renter  = address(0xBB);
    address internal feeRec  = address(0xFEE);

    function setUp() public {
        GameItems impl = new GameItems();
        items = GameItems(address(new ERC1967Proxy(
            address(impl),
            abi.encodeCall(GameItems.initialize, (admin, "ipfs://t/{id}.json"))
        )));
        items.grantRole(items.MINTER_ROLE(), admin);
        token  = new GameToken(admin, admin, 1_000_000e18);
        rental = new RentalVault(admin, feeRec);

        items.mint(owner, 5000, 10, "");
        token.transfer(renter, 1000e18);
    }

    function _list(uint256 amount, uint256 pricePerSec, uint64 minD, uint64 maxD)
        internal returns (uint256 id)
    {
        vm.startPrank(owner);
        items.setApprovalForAll(address(rental), true);
        id = rental.list(address(items), 5000, amount, address(token), pricePerSec, minD, maxD);
        vm.stopPrank();
    }

    // -----------------------------------------------------------------------
    // list() — ветки валидации входных данных
    // -----------------------------------------------------------------------

    // Branch: amount == 0 → InvalidAmount
    function test_list_revertsOnZeroAmount() public {
        vm.startPrank(owner);
        items.setApprovalForAll(address(rental), true);
        vm.expectRevert(RentalVault.InvalidAmount.selector);
        rental.list(address(items), 5000, 0, address(token), 1e15, 60, 7 days);
        vm.stopPrank();
    }

    // Branch: minDuration == 0 → InvalidDuration
    function test_list_revertsOnZeroMinDuration() public {
        vm.startPrank(owner);
        items.setApprovalForAll(address(rental), true);
        vm.expectRevert(RentalVault.InvalidDuration.selector);
        rental.list(address(items), 5000, 1, address(token), 1e15, 0, 7 days);
        vm.stopPrank();
    }

    // Branch: maxDuration < minDuration → InvalidDuration
    function test_list_revertsWhenMaxLessThanMin() public {
        vm.startPrank(owner);
        items.setApprovalForAll(address(rental), true);
        vm.expectRevert(RentalVault.InvalidDuration.selector);
        rental.list(address(items), 5000, 1, address(token), 1e15, 3600, 60);
        vm.stopPrank();
    }

    // Branch: itemContract == address(0) → ZeroAddress
    function test_list_revertsOnZeroItemContract() public {
        vm.startPrank(owner);
        vm.expectRevert(RentalVault.ZeroAddress.selector);
        rental.list(address(0), 5000, 1, address(token), 1e15, 60, 7 days);
        vm.stopPrank();
    }

    // Branch: payToken == address(0) → ZeroAddress
    function test_list_revertsOnZeroPayToken() public {
        vm.startPrank(owner);
        items.setApprovalForAll(address(rental), true);
        vm.expectRevert(RentalVault.ZeroAddress.selector);
        rental.list(address(items), 5000, 1, address(0), 1e15, 60, 7 days);
        vm.stopPrank();
    }

    // -----------------------------------------------------------------------
    // cancel() — ветки
    // -----------------------------------------------------------------------

    // Branch: status != Listed (уже Rented) → InvalidStatus
    function test_cancel_revertsWhenRented() public {
        uint256 id = _list(2, 1e15, 60, 7 days);
        vm.startPrank(renter);
        token.approve(address(rental), type(uint256).max);
        rental.rent(id, 1 hours);
        vm.stopPrank();
        vm.prank(owner);
        vm.expectRevert(RentalVault.InvalidStatus.selector);
        rental.cancel(id);
    }

    // Branch: status == Cancelled → InvalidStatus при повторном cancel
    function test_cancel_revertsWhenAlreadyCancelled() public {
        uint256 id = _list(2, 1e15, 60, 7 days);
        vm.prank(owner);
        rental.cancel(id);
        vm.prank(owner);
        vm.expectRevert(RentalVault.InvalidStatus.selector);
        rental.cancel(id);
    }

    // -----------------------------------------------------------------------
    // rent() — ветки
    // -----------------------------------------------------------------------

    // Branch: status != Listed → InvalidStatus
    function test_rent_revertsOnInvalidStatus() public {
        uint256 id = _list(2, 1e15, 60, 7 days);
        // Сначала отменяем листинг
        vm.prank(owner);
        rental.cancel(id);
        vm.startPrank(renter);
        token.approve(address(rental), type(uint256).max);
        vm.expectRevert(RentalVault.InvalidStatus.selector);
        rental.rent(id, 1 hours);
        vm.stopPrank();
    }

    // Branch: duration > maxDuration → InvalidDuration
    function test_rent_revertsOnDurationAboveMax() public {
        uint256 id = _list(2, 1e15, 60, 1 hours); // maxDuration = 1 час
        vm.startPrank(renter);
        token.approve(address(rental), type(uint256).max);
        vm.expectRevert(RentalVault.InvalidDuration.selector);
        rental.rent(id, 2 hours); // больше maxDuration
        vm.stopPrank();
    }

    // -----------------------------------------------------------------------
    // endRental() — ветки
    // -----------------------------------------------------------------------

    // Branch: status != Rented → NotRented
    function test_endRental_revertsOnNotRented() public {
        uint256 id = _list(2, 1e15, 60, 7 days);
        vm.expectRevert(RentalVault.NotRented.selector);
        rental.endRental(id);
    }

    // -----------------------------------------------------------------------
    // claimPayout() — ветка amount == 0 (early return, no transfer)
    // -----------------------------------------------------------------------

    function test_claimPayout_zeroAmount_noOp() public {
        // admin никогда не имел payout → payoutOf == 0 → should not revert
        uint256 balBefore = token.balanceOf(admin);
        rental.claimPayout(address(token));
        assertEq(token.balanceOf(admin), balBefore); // ничего не изменилось
    }

    // -----------------------------------------------------------------------
    // setFeeRecipient()
    // -----------------------------------------------------------------------

    function test_setFeeRecipient_updatesAddress() public {
        address newRec = address(0x1234);
        rental.setFeeRecipient(newRec);
        assertEq(rental.feeRecipient(), newRec);
    }

    function test_setFeeRecipient_revertsOnZero() public {
        vm.expectRevert(RentalVault.ZeroAddress.selector);
        rental.setFeeRecipient(address(0));
    }

    function test_setFeeRecipient_revertsForNonAdmin() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert();
        rental.setFeeRecipient(address(0x1234));
    }

    // -----------------------------------------------------------------------
    // setProtocolFeeBps() — happy path
    // -----------------------------------------------------------------------

    function test_setProtocolFee_updatesValue() public {
        rental.setProtocolFeeBps(500);
        assertEq(rental.protocolFeeBps(), 500);
    }

    // -----------------------------------------------------------------------
    // constructor — zero admin → ZeroAddress
    // -----------------------------------------------------------------------

    function test_constructor_revertsOnZeroAdmin() public {
        vm.expectRevert(RentalVault.ZeroAddress.selector);
        new RentalVault(address(0), feeRec);
    }

    function test_constructor_revertsOnZeroFeeRecipient() public {
        vm.expectRevert(RentalVault.ZeroAddress.selector);
        new RentalVault(admin, address(0));
    }

    // -----------------------------------------------------------------------
    // unpause()
    // -----------------------------------------------------------------------

    function test_unpause_reenablesList() public {
        rental.pause();
        rental.unpause();
        // должен успешно создать listing
        uint256 id = _list(1, 1e15, 60, 7 days);
        assertGt(id, 0);
    }

    // -----------------------------------------------------------------------
    // supportsInterface()
    // -----------------------------------------------------------------------

    function test_supportsInterface_erc1155Receiver() public view {
        bytes4 iface = 0x4e2312e0; // IERC1155Receiver
        assertTrue(rental.supportsInterface(iface));
    }

    function test_supportsInterface_accessControl() public view {
        bytes4 iface = type(IAccessControlIface).interfaceId;
        // AccessControl supportsInterface(0x01ffc9a7) — IAccessControl
        assertTrue(rental.supportsInterface(0x01ffc9a7));
    }
}

// Минимальный интерфейс чтобы получить interfaceId
interface IAccessControlIface {
    function hasRole(bytes32, address) external view returns (bool);
    function getRoleAdmin(bytes32) external view returns (bytes32);
    function grantRole(bytes32, address) external;
    function revokeRole(bytes32, address) external;
    function renounceRole(bytes32, address) external;
}

// ============================================================
// PriceOracle — extended branch coverage
// ============================================================

contract PriceOracleExtendedTest is Test {
    PriceOracle internal oracle;
    MockAggregator internal feed8;   // 8 decimals (стандарт)
    MockAggregator internal feed18;  // 18 decimals (= branch)
    MockAggregator internal feed20;  // 20 decimals (> 18 branch)
    address internal asset8  = address(0xA1);
    address internal asset18 = address(0xA2);
    address internal asset20 = address(0xA3);
    address internal admin   = address(this);

    function setUp() public {
        oracle  = new PriceOracle(admin);
        feed8   = new MockAggregator(2000e8,  8);
        feed18  = new MockAggregator(2000e18, 18);
        feed20  = new MockAggregator(int256(2000e20), 20);
        oracle.setFeed(asset8,  address(feed8),  1 hours);
        oracle.setFeed(asset18, address(feed18), 1 hours);
        oracle.setFeed(asset20, address(feed20), 1 hours);
    }

    // Branch: decimals == 18 → priceWad = raw (no scaling)
    function test_getLatestPrice_18decimals() public view {
        (uint256 p,) = oracle.getLatestPrice(asset18);
        assertEq(p, 2000e18);
    }

    // Branch: decimals > 18 → priceWad = raw / 10**(decimals-18)
    function test_getLatestPrice_above18decimals() public view {
        (uint256 p,) = oracle.getLatestPrice(asset20);
        assertEq(p, 2000e18);
    }

    // Branch: answeredInRound == 0 → InvalidPrice
    function test_getLatestPrice_revertsOnAnsweredInRoundZero() public {
        // MockAggregator возвращает roundId начиная с 1. Для answeredInRound==0
        // нужен кастомный mock.
        address assetZ = address(0xEE);
        ZeroRoundMock zeroMock = new ZeroRoundMock();
        oracle.setFeed(assetZ, address(zeroMock), 1 hours);
        vm.expectRevert();
        oracle.getLatestPrice(assetZ);
    }

    // Branch: setFeed feed == address(0) → ZeroAddress
    function test_setFeed_revertsOnZeroFeed() public {
        vm.expectRevert(PriceOracle.ZeroAddress.selector);
        oracle.setFeed(asset8, address(0), 1 hours);
    }

    // Branch: staleness == 0 → require revert
    function test_setFeed_revertsOnZeroStaleness() public {
        vm.expectRevert();
        oracle.setFeed(asset8, address(feed8), 0);
    }

    // feedOf() — покрывает непокрытую функцию
    function test_feedOf_returnsConfig() public view {
        PriceOracle.FeedConfig memory cfg = oracle.feedOf(asset8);
        assertTrue(cfg.registered);
        assertEq(cfg.decimals, 8);
        assertEq(cfg.staleness, 1 hours);
    }

    // feedOf() для незарегистрированного asset
    function test_feedOf_unregistered_notRegistered() public view {
        PriceOracle.FeedConfig memory cfg = oracle.feedOf(address(0xDEAD));
        assertFalse(cfg.registered);
    }

    // stalenessWindow() — покрывает непокрытую функцию
    function test_stalenessWindow_returnsCorrectValue() public view {
        assertEq(oracle.stalenessWindow(asset8), 1 hours);
    }

    function test_stalenessWindow_unregistered_returnsZero() public view {
        assertEq(oracle.stalenessWindow(address(0xDEAD)), 0);
    }

    // updatedAt возвращается корректно
    function test_getLatestPrice_returnsUpdatedAt() public view {
        (, uint256 updatedAt) = oracle.getLatestPrice(asset8);
        assertGt(updatedAt, 0);
    }
}

/// @dev Минимальный mock который возвращает answeredInRound == 0
contract ZeroRoundMock {
    function decimals() external pure returns (uint8) { return 8; }
    function latestRoundData() external view returns (
        uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound
    ) {
        return (1, 2000e8, block.timestamp, block.timestamp, 0); // answeredInRound == 0!
    }
}

// ============================================================
// MockAggregator — покрыть непокрытые функции
// ============================================================

contract MockAggregatorExtendedTest is Test {
    MockAggregator internal feed;

    function setUp() public {
        feed = new MockAggregator(2000e8, 8);
    }

    // description() — не вызывается в PriceOracle
    function test_description() public view {
        assertEq(feed.description(), "MockAggregator");
    }

    // version()
    function test_version() public view {
        assertEq(feed.version(), 4);
    }

    // getRoundData()
    function test_getRoundData() public view {
        (uint80 rId, int256 ans,, uint256 updAt, uint80 answeredIn) = feed.getRoundData(1);
        assertEq(ans, 2000e8);
        assertGt(rId, 0);
        assertGt(updAt, 0);
        assertEq(answeredIn, rId);
    }

    // setAnswer обновляет roundId
    function test_setAnswer_incrementsRoundId() public {
        (uint80 rId1,,,,) = feed.latestRoundData();
        feed.setAnswer(3000e8);
        (uint80 rId2, int256 ans,,,) = feed.latestRoundData();
        assertEq(rId2, rId1 + 1);
        assertEq(ans, 3000e8);
    }

    // setUpdatedAt
    function test_setUpdatedAt_changesTimestamp() public {
        uint256 ts = 1_000_000;
        feed.setUpdatedAt(ts);
        (,,,uint256 updAt,) = feed.latestRoundData();
        assertEq(updAt, ts);
    }

    // decimals
    function test_decimals() public view {
        assertEq(feed.decimals(), 8);
    }
}

// ============================================================
// PureMath — extended branch coverage
// ============================================================

contract PureMathExtendedTest is Test {
    PureMathWrapper internal w;

    function setUp() public {
        w = new PureMathWrapper();
    }

    // Branch: x < 2^128 → r = 1 (else-ветка первого if в sqrt)
    function test_sqrt_below2_128_usesLowInitialEstimate() public view {
        // x = 2^64 — ниже 2^128, значит r стартует с 1, а не 2^64
        uint256 x = 1 << 64;
        uint256 result = w.sqrt(x);
        assertEq(result, 1 << 32);
    }

    // Branch: t < 1<<64 (не входит в if (t >= 1<<64))
    function test_sqrt_below2_64_skipsBranch() public view {
        uint256 x = 1 << 32; // < 2^64
        assertEq(w.sqrt(x), 1 << 16);
    }

    // Branch: t < 1<<32
    function test_sqrt_below2_32_skipsBranch() public view {
        assertEq(w.sqrt(1 << 16), 1 << 8);
    }

    // Branch: t < 1<<16
    function test_sqrt_below2_16_skipsBranch() public view {
        assertEq(w.sqrt(1 << 8), 1 << 4);
    }

    // Branch: t < 1<<8
    function test_sqrt_below2_8_skipsBranch() public view {
        assertEq(w.sqrt(1 << 4), 1 << 2);
    }

    // Branch: t < 1<<4
    function test_sqrt_below2_4_skipsBranch() public view {
        assertEq(w.sqrt(4), 2);
    }

    // Branch: t < 1<<2 → r <<= 1 НЕ выполняется
    function test_sqrt_below2_2_skipsBranch() public view {
        // x = 2: t=2, не >= 4, не >= 2^2, значит r не сдвигается на 1
        assertEq(w.sqrt(2), 1);
    }

    // PureMath.min() — покрыть функцию (не вызывалась)
    function test_min_aLessThanB() public view {
        assertEq(w.min(3, 7), 3);
    }

    function test_min_aGreaterThanB() public view {
        assertEq(w.min(7, 3), 3);
    }

    function test_min_equal() public view {
        assertEq(w.min(5, 5), 5);
    }

    // PureMath.mulDiv()
    function test_mulDiv_delegatesToOZ() public view {
        assertEq(w.mulDiv(6, 3, 2), 9);
    }
}

// ============================================================
// LootBox — extended branch coverage
// ============================================================

contract LootBoxExtendedTest is Test {
    GameItems internal items;
    LootBox   internal lootBox;
    VRFCoordinatorV2_5Mock internal coord;
    address internal admin  = address(this);
    address internal player = address(0xCAFE);
    uint256 internal subId;

    function setUp() public {
        GameItems impl = new GameItems();
        items = GameItems(address(new ERC1967Proxy(
            address(impl),
            abi.encodeCall(GameItems.initialize, (admin, "ipfs://t/{id}.json"))
        )));
        items.grantRole(items.MINTER_ROLE(), admin);

        coord = new VRFCoordinatorV2_5Mock();
        subId = coord.createSubscription();
        coord.fundSubscription(subId, 100 ether);

        lootBox = new LootBox(
            address(coord), bytes32(uint256(1)), subId,
            IGameItems(address(items)), admin
        );
        coord.addConsumer(subId, address(lootBox));
        items.grantRole(items.MINTER_ROLE(), address(lootBox));

        LootBox.Reward[] memory r = new LootBox.Reward[](2);
        r[0] = LootBox.Reward({itemId: 10, amount: 1, weight: 7000});
        r[1] = LootBox.Reward({itemId: 20, amount: 1, weight: 3000});
        lootBox.setRewards(r);
    }

    // Branch: AlreadyFulfilled — выполнить fulfill дважды
    function test_fulfill_revertsOnAlreadyFulfilled() public {
        vm.prank(player);
        uint256 reqId = lootBox.openLootBox();

        uint256[] memory words = new uint256[](1);
        words[0] = 1;
        coord.fulfillRandomWordsWithOverride(reqId, address(lootBox), words);

        // Второй fulfill того же requestId должен revert
        vm.expectRevert(LootBox.AlreadyFulfilled.selector);
        coord.fulfillRandomWordsWithOverride(reqId, address(lootBox), words);
    }

    // setVRFConfig() — непокрытая функция
    function test_setVRFConfig_updatesAllFields() public {
        bytes32 newKeyHash = bytes32(uint256(42));
        uint256 newSubId = 999;
        uint16  newConfirmations = 5;
        uint32  newGasLimit = 300_000;

        lootBox.setVRFConfig(newKeyHash, newSubId, newConfirmations, newGasLimit);

        assertEq(lootBox.keyHash(), newKeyHash);
        assertEq(lootBox.subscriptionId(), newSubId);
        assertEq(lootBox.requestConfirmations(), newConfirmations);
        assertEq(lootBox.callbackGasLimit(), newGasLimit);
    }

    function test_setVRFConfig_revertsForNonAdmin() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert();
        lootBox.setVRFConfig(bytes32(0), 0, 3, 500_000);
    }

    // rewardCount() — покрыть view функцию
    function test_rewardCount_returnsCorrectLength() public view {
        assertEq(lootBox.rewardCount(), 2);
    }

    // pause/unpause
    function test_pause_andUnpause() public {
        lootBox.pause();
        assertTrue(lootBox.paused());
        lootBox.unpause();
        assertFalse(lootBox.paused());
    }

    // setRewards: нулевой weight → revert
    function test_setRewards_revertsOnZeroWeight() public {
        LootBox.Reward[] memory r = new LootBox.Reward[](1);
        r[0] = LootBox.Reward({itemId: 10, amount: 1, weight: 0});
        vm.expectRevert();
        lootBox.setRewards(r);
    }
}
