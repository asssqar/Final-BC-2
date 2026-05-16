// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

/// @title ItemFactory
/// @notice Factory deploying:
///         - **CREATE-based**: `deployERC1967Proxy` — vanilla `new ERC1967Proxy(...)`. Used for
///           the canonical GameItems proxy at deploy time.
///         - **CREATE2-based**: `deployERC1967ProxyDeterministic` — uses OpenZeppelin's
///           `Create2.deploy`, allowing the address to be precomputed off-chain. We use this for
///           "season" item shards whose addresses are referenced by the subgraph manifest before
///           deployment.
/// @dev    Required by §3.1: at least one Factory using both CREATE and CREATE2.
///         Both helpers are role-gated so only governance (or a designated factory admin) can
///         deploy new shards.
contract ItemFactory is AccessControl {
    bytes32 public constant FACTORY_ADMIN_ROLE = keccak256("FACTORY_ADMIN_ROLE");

    event ProxyDeployed(
        address indexed proxy, address indexed implementation, bytes32 indexed salt, bool create2
    );

    error DeployFailed();

    constructor(address admin) {
        require(admin != address(0), "ItemFactory: zero admin");
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(FACTORY_ADMIN_ROLE, admin);
    }

    /// @notice Standard CREATE deployment of an ERC1967Proxy fronting `implementation`.
    /// @param implementation Logic contract; must be already deployed and verified.
    /// @param data Initializer calldata (e.g. `abi.encodeCall(GameItems.initialize, (admin, uri))`).
    function deployERC1967Proxy(address implementation, bytes memory data)
        external
        onlyRole(FACTORY_ADMIN_ROLE)
        returns (address proxy)
    {
        proxy = address(new ERC1967Proxy(implementation, data));
        emit ProxyDeployed(proxy, implementation, bytes32(0), false);
    }

    /// @notice CREATE2 deployment of an ERC1967Proxy. Address is deterministic given
    ///         `(implementation, data, salt)`.
    function deployERC1967ProxyDeterministic(
        address implementation,
        bytes memory data,
        bytes32 salt
    ) external onlyRole(FACTORY_ADMIN_ROLE) returns (address proxy) {
        bytes memory bytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode, abi.encode(implementation, data)
        );
        proxy = Create2.deploy(0, salt, bytecode);
        emit ProxyDeployed(proxy, implementation, salt, true);
    }

    /// @notice Off-chain helper: precompute the CREATE2 proxy address.
    function predictProxyAddress(address implementation, bytes memory data, bytes32 salt)
        external
        view
        returns (address)
    {
        bytes memory bytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode, abi.encode(implementation, data)
        );
        return Create2.computeAddress(salt, keccak256(bytecode));
    }
}
