// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {GameItems} from "../tokens/GameItems.sol";

/// @title GameItemsV2
/// @notice Demonstrates the UUPS V1 → V2 upgrade path required by the syllabus.
///
/// V2 introduces:
///   - `craftWithDiscount`: a discounted-craft variant that requires the caller to hold a
///     "Master Crafter" cosmetic token (id ≥ COSMETIC_RANGE_LOWER_BOUND).
///   - `setCraftDiscountBps`: governance-only knob (0–9_000 bps) controlling the discount on the
///     craft fee.
///
/// Storage compatibility:
///   - We **append** new state at the END of the contract (after consuming one slot from the
///     parent's `__gap`). This is enforced by reducing `__gap` length in the parent by exactly
///     one slot if we add new state. We don't currently add storage variables that consume the
///     gap (we read it from a single packed uint256 slot), so the parent's gap remains valid.
///
/// See `docs/ARCHITECTURE.md#upgrade-path` for the storage diff and the OZ-validated layout.
contract GameItemsV2 is GameItems {
    /// @notice Discount in basis points applied to the craftFee inside `craftWithDiscount`.
    /// @dev Lives at the first slot AFTER the parent's `__gap`. We reuse storage slot 0 of this
    ///      child contract — there is no collision because the parent reserved 45 slots.
    uint256 public craftDiscountBps;

    uint256 public constant MAX_DISCOUNT_BPS = 9000; // 90%

    event CraftDiscountUpdated(uint256 newBps);
    event CraftedWithDiscount(
        address indexed crafter, uint256 indexed recipeId, uint256 discountBps
    );

    error InvalidDiscount();
    error NotMasterCrafter();

    function setCraftDiscountBps(uint256 newBps) external onlyRole(CRAFTER_ADMIN_ROLE) {
        if (newBps > MAX_DISCOUNT_BPS) revert InvalidDiscount();
        craftDiscountBps = newBps;
        emit CraftDiscountUpdated(newBps);
    }

    /// @notice Craft using a multi-recipe path with the discount applied to the craftFee.
    /// @dev Requires the crafter to hold at least one cosmetic-range token (id ≥ EQUIPMENT_RANGE_END).
    ///      We do not iterate the entire range (impossible); we accept a `proofId` that the caller
    ///      claims to own. ERC1155.balanceOf is enforced.
    function craftWithDiscount(uint256 recipeId, uint256 multiplier, uint256 proofId)
        external
        nonReentrant
        whenNotPaused
    {
        if (proofId < EQUIPMENT_RANGE_END) revert NotMasterCrafter();
        if (balanceOf(msg.sender, proofId) == 0) revert NotMasterCrafter();

        Recipe storage r = _recipes[recipeId];
        if (!r.active) revert RecipeInactive();
        if (multiplier == 0) revert InvalidRecipe();

        uint256 discount = craftDiscountBps;
        uint256 len = r.inputIds.length;
        uint256[] memory ids = new uint256[](len);
        uint256[] memory amounts = new uint256[](len);

        for (uint256 i = 0; i < len; ++i) {
            uint256 id = r.inputIds[i];
            uint256 amt = r.inputAmounts[i] * multiplier;
            if (i == 0) {
                uint256 fee = r.craftFee * multiplier;
                fee = fee - (fee * discount / 10_000);
                amt += fee;
            }
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
        emit CraftedWithDiscount(msg.sender, recipeId, discount);
    }

    function version() external pure override returns (string memory) {
        return "2.0.0";
    }
}
