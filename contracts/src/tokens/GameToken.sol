// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit, Nonces} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title GameToken (AETH)
/// @notice Governance + economy token of the Aetheria GameFi protocol.
///         - ERC20Votes: snapshotted voting power for the Governor.
///         - ERC20Permit (EIP-2612): gasless approvals for the AMM and vaults.
///         - Role-gated mint, capped supply, burnable by holders.
/// @dev `MINTER_ROLE` is granted only to the Timelock after deployment so that token issuance
///      becomes a governance decision (see deploy script + post-deploy verification).
contract GameToken is ERC20, ERC20Permit, ERC20Votes, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @notice Hard cap on circulating supply: 100,000,000 AETH (18 decimals).
    uint256 public constant MAX_SUPPLY = 100_000_000e18;

    error CapExceeded(uint256 attempted, uint256 max);

    constructor(address admin, address initialMinter, uint256 initialMint)
        ERC20("Aetheria", "AETH")
        ERC20Permit("Aetheria")
    {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, initialMinter);
        if (initialMint > 0) {
            _mint(admin, initialMint);
        }
    }

    /// @notice Role-gated mint, hard-capped at MAX_SUPPLY.
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        uint256 newSupply = totalSupply() + amount;
        if (newSupply > MAX_SUPPLY) revert CapExceeded(newSupply, MAX_SUPPLY);
        _mint(to, amount);
    }

    /// @notice Holder-initiated burn — reduces circulating supply.
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    // -----------------------------------------------------------------------
    // Required overrides
    // -----------------------------------------------------------------------

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Votes)
    {
        super._update(from, to, value);
    }

    function nonces(address owner)
        public
        view
        override(ERC20Permit, Nonces)
        returns (uint256)
    {
        return super.nonces(owner);
    }

    /// @dev Use timestamp-based clock so the Governor uses seconds, which is more L2-friendly
    ///      than block numbers (block production rates differ per rollup).
    function clock() public view override returns (uint48) {
        return uint48(block.timestamp);
    }

    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=timestamp";
    }
}
