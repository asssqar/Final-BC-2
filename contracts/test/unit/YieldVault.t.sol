// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {YieldVault} from "../../src/vaults/YieldVault.sol";
import {GameToken} from "../../src/tokens/GameToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract YieldVaultUnitTest is Test {
    GameToken internal token;
    YieldVault internal vault;
    address internal admin = address(this);
    address internal alice = address(0xA1);

    function setUp() public {
        token = new GameToken(admin, admin, 1_000_000e18);
        vault = new YieldVault(IERC20(address(token)), admin);
    }

    function test_metadata() public view {
        assertEq(vault.name(), "Aetheria Vault Share");
        assertEq(vault.symbol(), "vAETH");
        assertEq(address(vault.asset()), address(token));
    }

    function test_deposit_mintsShares() public {
        token.transfer(alice, 100e18);
        vm.startPrank(alice);
        token.approve(address(vault), 100e18);
        uint256 shares = vault.deposit(100e18, alice);
        vm.stopPrank();
        assertGt(shares, 0);
        assertEq(vault.balanceOf(alice), shares);
    }

    function test_withdraw_returnsAssets() public {
        token.transfer(alice, 100e18);
        vm.startPrank(alice);
        token.approve(address(vault), 100e18);
        vault.deposit(100e18, alice);
        uint256 maxShares = vault.balanceOf(alice);
        uint256 assets = vault.redeem(maxShares, alice, alice);
        vm.stopPrank();
        assertEq(assets, 100e18);
    }

    function test_pause_blocksDeposits() public {
        vault.pause();
        token.approve(address(vault), 1e18);
        vm.expectRevert();
        vault.deposit(1e18, admin);
    }

    function test_notifyRewards_increasesPricePerShare() public {
        token.transfer(alice, 100e18);
        vm.startPrank(alice);
        token.approve(address(vault), 100e18);
        vault.deposit(100e18, alice);
        vm.stopPrank();

        uint256 sharesBefore = vault.balanceOf(alice);
        uint256 assetsBefore = vault.convertToAssets(sharesBefore);

        // Send 50 AETH as rewards.
        vault.grantRole(vault.REWARD_DEPOSITOR_ROLE(), admin);
        token.approve(address(vault), 50e18);
        vault.notifyRewards(admin, 50e18);

        uint256 assetsAfter = vault.convertToAssets(sharesBefore);
        assertGt(assetsAfter, assetsBefore);
    }

    function test_inflationAttack_mitigated() public {
        // Donate 1 token directly
        token.transfer(address(vault), 1e18);
        // Attacker deposits 1 wei
        token.transfer(alice, 1);
        vm.startPrank(alice);
        token.approve(address(vault), 1);
        uint256 shares = vault.deposit(1, alice);
        vm.stopPrank();
        // With offset=6, the attacker's first-share gets virtual scaling — `shares` should be > 0.
        assertGt(shares, 0);
    }

    function test_decimalsOffset() public view {
        // Underlying has 18 decimals; vault should report 18 + 6 = 24
        assertEq(vault.decimals(), 24);
    }

    function test_unauthorizedReward_reverts() public {
        token.transfer(alice, 1e18);
        vm.startPrank(alice);
        token.approve(address(vault), 1e18);
        vm.expectRevert();
        vault.notifyRewards(alice, 1e18);
        vm.stopPrank();
    }
}
