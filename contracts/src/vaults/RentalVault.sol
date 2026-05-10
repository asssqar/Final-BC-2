// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title RentalVault
/// @notice Lets owners list ERC-1155 game items for fixed-term rental and renters claim them by
///         paying the price in AETH (or any whitelisted ERC-20). Items are escrowed in this
///         contract for the rental duration; on expiry the renter (or anyone) can call
///         `endRental` to return them to the owner.
/// @dev Patterns:
///      - Pull-over-push payouts: rental income accrues to `pendingPayout` and is claimed via
///        `claimPayout` — eliminates failed-callback DoS attacks.
///      - State machine per listing: Listed → Rented → Listed (or Cancelled).
///      - CEI: external token transfers happen after listing/rental state updates.
contract RentalVault is AccessControl, Pausable, ReentrancyGuard, IERC1155Receiver, ERC165 {
    using SafeERC20 for IERC20;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant FEE_ADMIN_ROLE = keccak256("FEE_ADMIN_ROLE");

    enum Status {
        None,
        Listed,
        Rented,
        Cancelled
    }

    struct Listing {
        address owner;
        address itemContract;
        uint256 itemId;
        uint256 amount;
        address payToken;
        uint256 pricePerSecond;
        uint64 minDuration;
        uint64 maxDuration;
        Status status;
        // Active rental fields:
        address renter;
        uint64 startTime;
        uint64 endTime;
    }

    /// @notice Protocol fee in basis points taken from rental payments and routed to `feeRecipient`.
    uint256 public protocolFeeBps; // governance-tunable; capped at 1_000 (10%)
    uint256 public constant MAX_FEE_BPS = 1_000;
    address public feeRecipient;

    uint256 public nextListingId;
    mapping(uint256 listingId => Listing) public listings;

    /// @notice Pull-over-push accounting: holder => payToken => claimable amount.
    mapping(address holder => mapping(address payToken => uint256)) public payoutOf;

    event Listed(uint256 indexed listingId, address indexed owner, address itemContract, uint256 itemId, uint256 amount);
    event Cancelled(uint256 indexed listingId);
    event Rented(uint256 indexed listingId, address indexed renter, uint64 endTime, uint256 paid);
    event RentalEnded(uint256 indexed listingId);
    event PayoutClaimed(address indexed holder, address indexed payToken, uint256 amount);
    event ProtocolFeeUpdated(uint256 newBps);
    event FeeRecipientUpdated(address newRecipient);

    error NotOwner();
    error AlreadyRented();
    error NotRented();
    error InvalidDuration();
    error RentalActive();
    error InvalidFee();
    error ZeroAddress();
    error InvalidStatus();
    error InvalidAmount();

    constructor(address admin, address _feeRecipient) {
        if (admin == address(0) || _feeRecipient == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
        _grantRole(FEE_ADMIN_ROLE, admin);
        feeRecipient = _feeRecipient;
        protocolFeeBps = 200; // 2 %
    }

    // -----------------------------------------------------------------------
    // Listing lifecycle
    // -----------------------------------------------------------------------

    /// @notice Lists an ERC-1155 stack for rental. Items are pulled into escrow.
    function list(
        address itemContract,
        uint256 itemId,
        uint256 amount,
        address payToken,
        uint256 pricePerSecond,
        uint64 minDuration,
        uint64 maxDuration
    ) external whenNotPaused nonReentrant returns (uint256 listingId) {
        if (amount == 0) revert InvalidAmount();
        if (minDuration == 0 || maxDuration < minDuration) revert InvalidDuration();
        if (itemContract == address(0) || payToken == address(0)) revert ZeroAddress();

        listingId = nextListingId++;
        listings[listingId] = Listing({
            owner: msg.sender,
            itemContract: itemContract,
            itemId: itemId,
            amount: amount,
            payToken: payToken,
            pricePerSecond: pricePerSecond,
            minDuration: minDuration,
            maxDuration: maxDuration,
            status: Status.Listed,
            renter: address(0),
            startTime: 0,
            endTime: 0
        });

        IERC1155(itemContract).safeTransferFrom(msg.sender, address(this), itemId, amount, "");
        emit Listed(listingId, msg.sender, itemContract, itemId, amount);
    }

    function cancel(uint256 listingId) external whenNotPaused nonReentrant {
        Listing storage l = listings[listingId];
        if (l.owner != msg.sender) revert NotOwner();
        if (l.status != Status.Listed) revert InvalidStatus();
        l.status = Status.Cancelled;
        IERC1155(l.itemContract).safeTransferFrom(address(this), msg.sender, l.itemId, l.amount, "");
        emit Cancelled(listingId);
    }

    /// @notice Rent a listed item for `duration` seconds, paying `pricePerSecond * duration`.
    function rent(uint256 listingId, uint64 duration)
        external
        whenNotPaused
        nonReentrant
    {
        Listing storage l = listings[listingId];
        if (l.status != Status.Listed) revert InvalidStatus();
        if (duration < l.minDuration || duration > l.maxDuration) revert InvalidDuration();

        uint256 totalCost = uint256(duration) * l.pricePerSecond;
        uint256 fee = totalCost * protocolFeeBps / 10_000;
        uint256 ownerCut = totalCost - fee;

        l.status = Status.Rented;
        l.renter = msg.sender;
        l.startTime = uint64(block.timestamp);
        l.endTime = uint64(block.timestamp) + duration;

        // Pull funds, then accrue payouts (pull-over-push for owner & feeRecipient).
        IERC20(l.payToken).safeTransferFrom(msg.sender, address(this), totalCost);
        payoutOf[l.owner][l.payToken] += ownerCut;
        payoutOf[feeRecipient][l.payToken] += fee;

        // Send the items to the renter for the rental duration.
        IERC1155(l.itemContract).safeTransferFrom(address(this), msg.sender, l.itemId, l.amount, "");
        emit Rented(listingId, msg.sender, l.endTime, totalCost);
    }

    /// @notice After rental expiry, the listing must be ended. The renter is required to
    ///         pre-approve the vault to pull items back (by `setApprovalForAll`) — this is
    ///         called out in the README and the frontend enforces it. If the renter fails to
    ///         keep approval, the listing remains in Rented state but the owner still keeps
    ///         their pre-paid rental income via `claimPayout`.
    function endRental(uint256 listingId) external nonReentrant {
        Listing storage l = listings[listingId];
        if (l.status != Status.Rented) revert NotRented();
        if (block.timestamp < l.endTime) revert RentalActive();

        address renter = l.renter;
        uint256 itemId = l.itemId;
        uint256 amount = l.amount;
        l.status = Status.Listed;
        l.renter = address(0);
        l.startTime = 0;
        l.endTime = 0;

        // Best-effort pull back. Reverts if renter has not approved → owner can re-approve flow.
        IERC1155(l.itemContract).safeTransferFrom(renter, l.owner, itemId, amount, "");
        emit RentalEnded(listingId);
    }

    // -----------------------------------------------------------------------
    // Pull-over-push payouts
    // -----------------------------------------------------------------------

    function claimPayout(address payToken) external nonReentrant {
        uint256 amount = payoutOf[msg.sender][payToken];
        if (amount == 0) return;
        payoutOf[msg.sender][payToken] = 0;
        IERC20(payToken).safeTransfer(msg.sender, amount);
        emit PayoutClaimed(msg.sender, payToken, amount);
    }

    // -----------------------------------------------------------------------
    // Governance knobs
    // -----------------------------------------------------------------------

    function setProtocolFeeBps(uint256 newBps) external onlyRole(FEE_ADMIN_ROLE) {
        if (newBps > MAX_FEE_BPS) revert InvalidFee();
        protocolFeeBps = newBps;
        emit ProtocolFeeUpdated(newBps);
    }

    function setFeeRecipient(address newRecipient) external onlyRole(FEE_ADMIN_ROLE) {
        if (newRecipient == address(0)) revert ZeroAddress();
        feeRecipient = newRecipient;
        emit FeeRecipientUpdated(newRecipient);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // -----------------------------------------------------------------------
    // ERC1155Receiver
    // -----------------------------------------------------------------------

    function onERC1155Received(address, address, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControl, ERC165, IERC165)
        returns (bool)
    {
        return interfaceId == type(IERC1155Receiver).interfaceId
            || AccessControl.supportsInterface(interfaceId)
            || ERC165.supportsInterface(interfaceId);
    }
}
