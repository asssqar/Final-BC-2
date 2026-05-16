// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, StdInvariant} from "forge-std/Test.sol";
import {YieldVault} from "../../src/vaults/YieldVault.sol";
import {GameToken} from "../../src/tokens/GameToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract VaultHandler is Test {
    YieldVault public vault;
    GameToken public token;
    address public actor = makeAddr("vactor");

    constructor(YieldVault _v, GameToken _t) {
        vault = _v;
        token = _t;
        deal(address(_t), address(this), 1_000_000e18);
        token.transfer(actor, 1_000_000e18);
        vm.prank(actor);
        token.approve(address(vault), type(uint256).max);
    }

    function deposit(uint256 amt) external {
        amt = bound(amt, 1, token.balanceOf(actor));
        if (amt == 0) return;
        vm.prank(actor);
        vault.deposit(amt, actor);
    }

    function withdraw(uint256 sh) external {
        uint256 max = vault.balanceOf(actor);
        sh = bound(sh, 0, max);
        if (sh == 0) return;
        vm.prank(actor);
        vault.redeem(sh, actor, actor);
    }
}

contract VaultInvariantTest is StdInvariant, Test {
    YieldVault internal vault;
    GameToken internal token;
    VaultHandler internal handler;

    function setUp() public {
        token = new GameToken(address(this), address(this), 100_000_000e18);
        vault = new YieldVault(IERC20(address(token)), address(this));
        handler = new VaultHandler(vault, token);
        targetContract(address(handler));
    }

    /// @notice totalAssets ≥ totalSupply / 1e6 (decimals offset). Approximation: vault never owes
    ///         more than it holds.
    function invariant_solvent() public view {
        uint256 totalAssets = token.balanceOf(address(vault));
        uint256 totalShares = vault.totalSupply();
        // convertToAssets gives the assets corresponding to all shares; should be ≤ totalAssets.
        uint256 owed = vault.convertToAssets(totalShares);
        assertLe(owed, totalAssets);
    }
}
