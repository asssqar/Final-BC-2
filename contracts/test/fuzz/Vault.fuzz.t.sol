// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {YieldVault} from "../../src/vaults/YieldVault.sol";
import {GameToken} from "../../src/tokens/GameToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract VaultFuzzTest is Test {
    GameToken internal token;
    YieldVault internal vault;
    address internal admin = address(this);
    address internal alice = address(0xA1);

    function setUp() public {
        token = new GameToken(admin, admin, 100_000_000e18);
        vault = new YieldVault(IERC20(address(token)), admin);
    }

    function testFuzz_deposit_redeem_roundsConservatively(uint256 amount) public {
        amount = bound(amount, 1e6, 1_000_000e18);
        token.transfer(alice, amount);
        vm.startPrank(alice);
        token.approve(address(vault), amount);
        uint256 shares = vault.deposit(amount, alice);
        uint256 redeemed = vault.redeem(shares, alice, alice);
        vm.stopPrank();
        // Inflation-safe rounding can give back ≤ amount but never more.
        assertLe(redeemed, amount);
    }

    function testFuzz_deposit_neverMintsMoreSharesThanPreview(uint256 amount) public {
        amount = bound(amount, 1, 1_000_000e18);
        token.transfer(alice, amount);
        vm.startPrank(alice);
        token.approve(address(vault), amount);
        uint256 expected = vault.previewDeposit(amount);
        uint256 actual = vault.deposit(amount, alice);
        vm.stopPrank();
        assertEq(actual, expected);
    }

    function testFuzz_assetsToShares_roundtrip(uint256 amount) public view {
        amount = bound(amount, 1, 1_000_000e18);
        uint256 sh = vault.convertToShares(amount);
        uint256 back = vault.convertToAssets(sh);
        // Round-trip rounds down → result ≤ original.
        assertLe(back, amount);
    }
}
