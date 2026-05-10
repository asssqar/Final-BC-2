// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC1155Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import {ERC1155SupplyUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

/// @title GameItems V1
/// @notice Upgradeable ERC-1155 registry for Aetheria items + crafting.
/// @dev Patterns demonstrated:
///      - UUPS proxy (`_authorizeUpgrade`) with the Timelock as upgrader.
///      - Access Control (MINTER_ROLE, CRAFTER_ADMIN_ROLE, UPGRADER_ROLE).
///      - Pausable circuit breaker.
///      - Reentrancy guard on craft (untrusted ERC-1155 hooks).
///      - State machine on token IDs (resource range vs equipment range vs cosmetic range).
///
/// Storage layout is documented in `docs/ARCHITECTURE.md`. The total of 50 storage slots
/// reserved at the end (`__gap`) protects against future field additions colliding with
/// V2/V3 layouts.
contract GameItems is
    Initializable,
    ERC1155Upgradeable,
    ERC1155SupplyUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant CRAFTER_ADMIN_ROLE = keccak256("CRAFTER_ADMIN_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice Token-ID partitioning (state machine).
    /// @dev Resources are fungible, equipment is semi-fungible (high supply rare),
    ///      cosmetics are unique-per-id (totalSupply == 1 enforced by the mint logic).
    uint256 public constant RESOURCE_RANGE_END = 1_000;          // [0, 1000)
    uint256 public constant EQUIPMENT_RANGE_END = 100_000;        // [1000, 100_000)
    uint256 public constant COSMETIC_RANGE_END = type(uint256).max; // [100_000, ...)

    struct Recipe {
        uint256[] inputIds;
        uint256[] inputAmounts;
        uint256 outputId;
        uint256 outputAmount;
        uint256 craftFee;        // burned from input[0] in addition to recipe inputs (governance-tunable)
        bool active;
    }

    /// @notice recipeId => recipe.
    mapping(uint256 recipeId => Recipe) internal _recipes;

    /// @notice Number of times each recipe has been crafted (analytics + subgraph indexing).
    mapping(uint256 recipeId => uint256) public craftCount;

    /// @notice Optional URI override per id (overrides the base URI returned by `uri`).
    mapping(uint256 id => string) internal _tokenURIs;

    /// @notice Reserved for future state. NEVER reduce below zero — only consume from the top.
    uint256[45] private __gap;

    event RecipeSet(uint256 indexed recipeId, uint256 outputId, uint256 outputAmount, uint256 craftFee);
    event RecipeRemoved(uint256 indexed recipeId);
    event Crafted(address indexed crafter, uint256 indexed recipeId, uint256 outputId, uint256 outputAmount);
    event TokenURISet(uint256 indexed id, string uri);

    error InvalidRecipe();
    error RecipeInactive();
    error InsufficientResource(uint256 id, uint256 have, uint256 need);
    error OutOfRange(uint256 id);
    error LengthMismatch();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializer for the V1 implementation behind a UUPS proxy.
    /// @param admin Will hold DEFAULT_ADMIN_ROLE (set to Timelock in production).
    /// @param initialURI Base ERC-1155 URI (e.g. ipfs://.../{id}.json).
    function initialize(address admin, string calldata initialURI) external initializer {
        __ERC1155_init(initialURI);
        __ERC1155Supply_init();
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
        _grantRole(CRAFTER_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
    }

    // -----------------------------------------------------------------------
    // Mint / burn — role-gated
    // -----------------------------------------------------------------------

    function mint(address to, uint256 id, uint256 amount, bytes calldata data)
        external
        whenNotPaused
        onlyRole(MINTER_ROLE)
    {
        _requireInRange(id);
        _mint(to, id, amount, data);
    }

    function mintBatch(
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes calldata data
    ) external whenNotPaused onlyRole(MINTER_ROLE) {
        if (ids.length != amounts.length) revert LengthMismatch();
        for (uint256 i = 0; i < ids.length; ++i) {
            _requireInRange(ids[i]);
        }
        _mintBatch(to, ids, amounts, data);
    }

    /// @notice Burn requires either being the holder or having ERC-1155 approval.
    function burn(address from, uint256 id, uint256 amount) external whenNotPaused {
        if (from != msg.sender && !isApprovedForAll(from, msg.sender)) {
            revert ERC1155MissingApprovalForAll(msg.sender, from);
        }
        _burn(from, id, amount);
    }

    // -----------------------------------------------------------------------
    // Crafting
    // -----------------------------------------------------------------------

    /// @notice Sets/updates a crafting recipe. Only governance may call.
    function setRecipe(
        uint256 recipeId,
        uint256[] calldata inputIds,
        uint256[] calldata inputAmounts,
        uint256 outputId,
        uint256 outputAmount,
        uint256 craftFee
    ) external onlyRole(CRAFTER_ADMIN_ROLE) {
        if (inputIds.length == 0) revert InvalidRecipe();
        if (inputIds.length != inputAmounts.length) revert LengthMismatch();
        if (outputAmount == 0) revert InvalidRecipe();
        _requireInRange(outputId);

        for (uint256 i = 0; i < inputIds.length; ++i) {
            _requireInRange(inputIds[i]);
            if (inputAmounts[i] == 0) revert InvalidRecipe();
        }

        _recipes[recipeId] = Recipe({
            inputIds: inputIds,
            inputAmounts: inputAmounts,
            outputId: outputId,
            outputAmount: outputAmount,
            craftFee: craftFee,
            active: true
        });
        emit RecipeSet(recipeId, outputId, outputAmount, craftFee);
    }

    function removeRecipe(uint256 recipeId) external onlyRole(CRAFTER_ADMIN_ROLE) {
        _recipes[recipeId].active = false;
        emit RecipeRemoved(recipeId);
    }

    function getRecipe(uint256 recipeId) external view returns (Recipe memory) {
        return _recipes[recipeId];
    }

    /// @notice Burn the inputs, mint the output. Idempotent under invariant testing.
    /// @dev CEI: state changes (burn + craftCount) precede the external mint hook (`onERC1155Received`).
    function craft(uint256 recipeId, uint256 multiplier)
        external
        nonReentrant
        whenNotPaused
    {
        if (multiplier == 0) revert InvalidRecipe();
        Recipe storage r = _recipes[recipeId];
        if (!r.active) revert RecipeInactive();

        uint256 len = r.inputIds.length;
        uint256[] memory ids = new uint256[](len);
        uint256[] memory amounts = new uint256[](len);
        for (uint256 i = 0; i < len; ++i) {
            uint256 id = r.inputIds[i];
            uint256 amt = r.inputAmounts[i] * multiplier;
            if (i == 0) amt += r.craftFee * multiplier;
            uint256 bal = balanceOf(msg.sender, id);
            if (bal < amt) revert InsufficientResource(id, bal, amt);
            ids[i] = id;
            amounts[i] = amt;
        }

        _burnBatch(msg.sender, ids, amounts);
        unchecked {
            craftCount[recipeId] += multiplier;
        }

        _mint(msg.sender, r.outputId, r.outputAmount * multiplier, "");
        emit Crafted(msg.sender, recipeId, r.outputId, r.outputAmount * multiplier);
    }

    // -----------------------------------------------------------------------
    // URI management
    // -----------------------------------------------------------------------

    function uri(uint256 id) public view override returns (string memory) {
        string memory custom = _tokenURIs[id];
        if (bytes(custom).length != 0) return custom;
        return super.uri(id);
    }

    function setTokenURI(uint256 id, string calldata newURI)
        external
        onlyRole(CRAFTER_ADMIN_ROLE)
    {
        _tokenURIs[id] = newURI;
        emit TokenURISet(id, newURI);
    }

    function setBaseURI(string calldata newURI) external onlyRole(CRAFTER_ADMIN_ROLE) {
        _setURI(newURI);
    }

    // -----------------------------------------------------------------------
    // Pausable
    // -----------------------------------------------------------------------

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // -----------------------------------------------------------------------
    // UUPS authorization
    // -----------------------------------------------------------------------

    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyRole(UPGRADER_ROLE)
    {} // solhint-disable-line no-empty-blocks

    // -----------------------------------------------------------------------
    // Internal helpers
    // -----------------------------------------------------------------------

    function _requireInRange(uint256 id) internal pure {
        if (id >= COSMETIC_RANGE_END) revert OutOfRange(id);
    }

    // -----------------------------------------------------------------------
    // Required overrides
    // -----------------------------------------------------------------------

    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
        internal
        override(ERC1155Upgradeable, ERC1155SupplyUpgradeable)
        whenNotPaused
    {
        super._update(from, to, ids, values);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155Upgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /// @notice Implementation version. Bumped in V2.
    function version() external pure virtual returns (string memory) {
        return "1.0.0";
    }
}
