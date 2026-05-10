// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/// @notice Minimal VRF v2.5 coordinator mock used in unit tests for `LootBox`.
/// @dev We do **not** inherit the full `IVRFCoordinatorV2Plus` interface to keep this mock small;
///      `LootBox` only ever calls `requestRandomWords` on the coordinator (via
///      `VRFConsumerBaseV2Plus.s_vrfCoordinator`), and the consumer accepts any address that
///      can be cast to that interface. Random word delivery is manual & deterministic.
contract VRFCoordinatorV2_5Mock {
    uint256 public nextRequestId = 1;
    uint256 public nextSubId = 1;

    struct PendingRequest {
        address consumer;
        uint32 numWords;
        uint256 subId;
        bool fulfilled;
    }

    mapping(uint256 => PendingRequest) public pending;
    mapping(uint256 => uint256) public balances;
    mapping(uint256 => mapping(address => bool)) public consumers;

    function createSubscription() external returns (uint256 subId) {
        subId = nextSubId++;
    }

    function fundSubscription(uint256 subId, uint256 amount) external {
        balances[subId] += amount;
    }

    function addConsumer(uint256 subId, address consumer) external {
        consumers[subId][consumer] = true;
    }

    function requestRandomWords(VRFV2PlusClient.RandomWordsRequest calldata req)
        external
        returns (uint256 requestId)
    {
        requestId = nextRequestId++;
        pending[requestId] = PendingRequest({
            consumer: msg.sender,
            numWords: req.numWords,
            subId: req.subId,
            fulfilled: false
        });
    }

    function fulfillRandomWordsWithOverride(
        uint256 requestId,
        address consumer,
        uint256[] calldata words
    ) external {
        require(pending[requestId].consumer == consumer, "wrong consumer");
        pending[requestId].fulfilled = true;
        // `VRFConsumerBaseV2Plus` exposes `rawFulfillRandomWords(uint256,uint256[])` only for the
        // coordinator address. By calling from this mock (which **is** the coordinator from the
        // consumer's POV) the gate passes.
        (bool ok,) = consumer.call(
            abi.encodeWithSignature("rawFulfillRandomWords(uint256,uint256[])", requestId, words)
        );
        require(ok, "fulfill failed");
    }
}
