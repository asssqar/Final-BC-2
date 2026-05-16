// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {
    VRFConsumerBaseV2Plus
} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {IGameItems} from "../interfaces/IGameItems.sol";

/// @title LootBox
/// @notice Chainlink VRF v2.5-powered loot drop. Players "open" a loot box (paying nothing in
///         this implementation — the entry cost is the burn of a key item, see `setKeyItem`),
///         which schedules a VRF request. The fulfillment callback assigns the player one prize
///         from a weighted reward table, then mints it on the upgradeable GameItems contract.
/// @dev    - VRFConsumerBaseV2Plus enforces only the coordinator can callback.
///         - The reward table is governance-tunable (DAO-owned key requirement of §3.1).
///         - We never use `block.timestamp` or `blockhash` for randomness (§3.2).
///         - State machine: Pending → Fulfilled per request id.
contract LootBox is VRFConsumerBaseV2Plus, AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant LOOT_ADMIN_ROLE = keccak256("LOOT_ADMIN_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    struct Reward {
        uint256 itemId;
        uint256 amount;
        uint32 weight;
    }

    struct PendingRequest {
        address player;
        bool fulfilled;
    }

    IGameItems public immutable gameItems;

    bytes32 public keyHash;
    uint256 public subscriptionId;
    uint16 public requestConfirmations = 3;
    uint32 public callbackGasLimit = 500_000;
    uint32 public constant NUM_WORDS = 1;

    /// @notice Optional ERC-1155 "key" that must be burned to open a box. id == 0 means disabled.
    uint256 public keyItemId;
    uint256 public keyItemAmount;

    Reward[] public rewards;
    uint256 public totalWeight;

    mapping(uint256 requestId => PendingRequest) public requests;

    event LootBoxOpened(address indexed player, uint256 indexed requestId);
    event LootBoxFulfilled(
        address indexed player, uint256 indexed requestId, uint256 itemId, uint256 amount
    );
    event RewardsUpdated();
    event KeyItemUpdated(uint256 itemId, uint256 amount);
    event VRFConfigUpdated(bytes32 keyHash, uint256 subId, uint16 confirmations, uint32 gasLimit);

    error NoRewards();
    error NoKey();
    error AlreadyFulfilled();

    constructor(
        address vrfCoordinator,
        bytes32 _keyHash,
        uint256 _subId,
        IGameItems _gameItems,
        address admin
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        keyHash = _keyHash;
        subscriptionId = _subId;
        gameItems = _gameItems;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(LOOT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
    }

    // -----------------------------------------------------------------------
    // Player entrypoint
    // -----------------------------------------------------------------------

    /// @notice Burn the configured key (if any) and request a random reward via Chainlink VRF.
    /// @return requestId Subgraph clients can correlate this with the eventual fulfillment.
    function openLootBox() external nonReentrant whenNotPaused returns (uint256 requestId) {
        if (rewards.length == 0 || totalWeight == 0) revert NoRewards();
        if (keyItemAmount > 0) {
            uint256 bal = gameItems.balanceOf(msg.sender, keyItemId);
            if (bal < keyItemAmount) revert NoKey();
            gameItems.burn(msg.sender, keyItemId, keyItemAmount);
        }

        VRFV2PlusClient.RandomWordsRequest memory req = VRFV2PlusClient.RandomWordsRequest({
            keyHash: keyHash,
            subId: subscriptionId,
            requestConfirmations: requestConfirmations,
            callbackGasLimit: callbackGasLimit,
            numWords: NUM_WORDS,
            extraArgs: VRFV2PlusClient._argsToBytes(
                VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
            )
        });
        requestId = s_vrfCoordinator.requestRandomWords(req);
        requests[requestId] = PendingRequest({player: msg.sender, fulfilled: false});
        emit LootBoxOpened(msg.sender, requestId);
    }

    /// @notice Coordinator callback. Picks a weighted-random reward and mints it.
    /// @dev `gameItems.mint` requires this contract to hold MINTER_ROLE on GameItems.
    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords)
        internal
        override
    {
        PendingRequest storage r = requests[requestId];
        if (r.fulfilled) revert AlreadyFulfilled();
        r.fulfilled = true;

        uint256 word = randomWords[0];
        uint256 pick = word % totalWeight;
        uint256 cumulative;
        Reward memory chosen = rewards[0];
        for (uint256 i = 0; i < rewards.length; ++i) {
            cumulative += rewards[i].weight;
            if (pick < cumulative) {
                chosen = rewards[i];
                break;
            }
        }

        gameItems.mint(r.player, chosen.itemId, chosen.amount, "");
        emit LootBoxFulfilled(r.player, requestId, chosen.itemId, chosen.amount);
    }

    // -----------------------------------------------------------------------
    // Governance — reward table & VRF config
    // -----------------------------------------------------------------------

    function setRewards(Reward[] calldata newRewards) external onlyRole(LOOT_ADMIN_ROLE) {
        delete rewards;
        uint256 sum;
        for (uint256 i = 0; i < newRewards.length; ++i) {
            require(newRewards[i].weight > 0, "LootBox: zero weight");
            rewards.push(newRewards[i]);
            sum += newRewards[i].weight;
        }
        totalWeight = sum;
        emit RewardsUpdated();
    }

    function setKeyItem(uint256 itemId, uint256 amount) external onlyRole(LOOT_ADMIN_ROLE) {
        keyItemId = itemId;
        keyItemAmount = amount;
        emit KeyItemUpdated(itemId, amount);
    }

    function setVRFConfig(bytes32 _keyHash, uint256 _subId, uint16 _confirmations, uint32 _gasLimit)
        external
        onlyRole(LOOT_ADMIN_ROLE)
    {
        keyHash = _keyHash;
        subscriptionId = _subId;
        requestConfirmations = _confirmations;
        callbackGasLimit = _gasLimit;
        emit VRFConfigUpdated(_keyHash, _subId, _confirmations, _gasLimit);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function rewardCount() external view returns (uint256) {
        return rewards.length;
    }
}
