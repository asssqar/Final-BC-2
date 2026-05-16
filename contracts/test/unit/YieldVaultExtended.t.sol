// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {YieldVault} from "../../src/vaults/YieldVault.sol";
import {GameToken} from "../../src/tokens/GameToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/// @title YieldVaultExtendedTest
/// @notice Covers branches missing from YieldVault.t.sol to push the contract above 90 % line coverage.
contract YieldVaultExtendedTest is Test {
    GameToken internal token;
    YieldVault internal vault;
    address internal admin = address(this);
    address internal alice = address(0xA1);
    address internal bob = address(0xB2);
    address internal depositor = address(0xD1);

    function setUp() public {
        token = new GameToken(admin, admin, 10_000_000e18);
        vault = new YieldVault(IERC20(address(token)), admin);

        token.transfer(alice, 1_000_000e18);
        token.transfer(bob, 1_000_000e18);

        vm.prank(alice);
        token.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        token.approve(address(vault), type(uint256).max);
    }

    // -----------------------------------------------------------------------
    // Role constants
    // -----------------------------------------------------------------------

    function test_roleConstants() public view {
        assertEq(vault.PAUSER_ROLE(), keccak256("PAUSER_ROLE"));
        assertEq(vault.REWARD_DEPOSITOR_ROLE(), keccak256("REWARD_DEPOSITOR_ROLE"));
    }

    // -----------------------------------------------------------------------
    // mint() happy path
    // -----------------------------------------------------------------------

    function test_mint_mintsExactShares() public {
        uint256 sharesToMint = 1000e24;
        vm.prank(alice);
        uint256 preview = vault.previewMint(sharesToMint);
        vm.prank(alice);
        uint256 assetsUsed = vault.mint(sharesToMint, alice);
        assertEq(vault.balanceOf(alice), sharesToMint);
        assertEq(assetsUsed, preview);
    }

    function test_mint_toReceiver() public {
        vm.prank(alice);
        vault.mint(500e24, bob);
        assertEq(vault.balanceOf(bob), 500e24);
    }

    // -----------------------------------------------------------------------
    // withdraw() happy path
    // -----------------------------------------------------------------------

    function test_withdraw_burnsCorrectShares() public {
        vm.prank(alice);
        vault.deposit(100e18, alice);

        uint256 sharesBefore = vault.balanceOf(alice);
        uint256 maxAssets = vault.maxWithdraw(alice);

        vm.prank(alice);
        uint256 sharesBurned = vault.withdraw(maxAssets, alice, alice);

        assertEq(vault.balanceOf(alice), sharesBefore - sharesBurned);
    }

    function test_withdraw_byApprovedSpender() public {
        vm.prank(alice);
        vault.deposit(100e18, alice);

        vm.prank(alice);
        vault.approve(bob, type(uint256).max);

        uint256 maxAssets = vault.maxWithdraw(alice);
        uint256 bobBefore = token.balanceOf(bob);
        vm.prank(bob);
        vault.withdraw(maxAssets, bob, alice);
        assertGt(token.balanceOf(bob), bobBefore);
    }

    // -----------------------------------------------------------------------
    // pause() blocks all four entry points
    // -----------------------------------------------------------------------

    function test_pause_blocksMint() public {
        vault.pause();
        vm.prank(alice);
        vm.expectRevert();
        vault.mint(1e24, alice);
    }

    function test_pause_blocksWithdraw() public {
        vm.prank(alice);
        vault.deposit(100e18, alice);

        vault.pause();
        uint256 maxAssets = vault.maxWithdraw(alice);
        vm.assume(maxAssets > 0);
        vm.prank(alice);
        vm.expectRevert();
        vault.withdraw(maxAssets, alice, alice);
    }

    function test_pause_blocksRedeem() public {
        vm.prank(alice);
        vault.deposit(100e18, alice);

        vault.pause();
        uint256 shares = vault.balanceOf(alice);
        vm.prank(alice);
        vm.expectRevert();
        vault.redeem(shares, alice, alice);
    }

    // -----------------------------------------------------------------------
    // unpause() re-enables operations
    // -----------------------------------------------------------------------

    function test_unpause_reenablesDeposit() public {
        vault.pause();
        vault.unpause();
        vm.prank(alice);
        uint256 shares = vault.deposit(100e18, alice);
        assertGt(shares, 0);
    }

    function test_unpause_reenablesMint() public {
        vault.pause();
        vault.unpause();
        vm.prank(alice);
        uint256 assets = vault.mint(1000e24, alice);
        assertGt(assets, 0);
    }

    // -----------------------------------------------------------------------
    // unpause() / pause() by non-pauser reverts
    // -----------------------------------------------------------------------

    function test_unpause_nonPauser_reverts() public {
        vault.pause();
        vm.prank(alice);
        vm.expectRevert();
        vault.unpause();
    }

    function test_pause_nonPauser_reverts() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.pause();
    }

    // -----------------------------------------------------------------------
    // notifyRewards while paused reverts
    // -----------------------------------------------------------------------

    function test_notifyRewards_whenPaused_reverts() public {
        vault.grantRole(vault.REWARD_DEPOSITOR_ROLE(), admin);
        token.approve(address(vault), 50e18);
        vault.pause();
        vm.expectRevert();
        vault.notifyRewards(admin, 50e18);
    }

    // -----------------------------------------------------------------------
    // notifyRewards with zero amount (should succeed)
    // -----------------------------------------------------------------------

    function test_notifyRewards_zeroAmount() public {
        vault.grantRole(vault.REWARD_DEPOSITOR_ROLE(), admin);
        token.approve(address(vault), 0);
        vault.notifyRewards(admin, 0);
    }

    // -----------------------------------------------------------------------
    // OZ ERC4626 maxDeposit/maxMint: when paused the OZ base returns max uint256
    // (OZ v5 does not override these for Pausable — YieldVault overrides deposit/mint
    //  to revert, but maxDeposit/maxMint still return type(uint256).max from OZ base).
    // We verify the actual behaviour here so the tests reflect the real contract.
    // -----------------------------------------------------------------------

    function test_maxDeposit_paused_returnsMaxUint() public {
        vault.pause();
        // OZ ERC4626 base: maxDeposit returns type(uint256).max unless overridden
        assertEq(vault.maxDeposit(alice), type(uint256).max);
    }

    function test_maxMint_paused_returnsMaxUint() public {
        vault.pause();
        assertEq(vault.maxMint(alice), type(uint256).max);
    }

    function test_maxWithdraw_paused_nonZero() public {
        vm.prank(alice);
        vault.deposit(100e18, alice);
        vault.pause();
        // maxWithdraw is based on convertToAssets(balanceOf) which still works when paused
        // The actual withdraw will revert, but maxWithdraw returns the theoretical max
        uint256 max = vault.maxWithdraw(alice);
        assertGt(max, 0);
    }

    function test_maxRedeem_paused_nonZero() public {
        vm.prank(alice);
        vault.deposit(100e18, alice);
        vault.pause();
        uint256 max = vault.maxRedeem(alice);
        assertGt(max, 0);
    }

    // -----------------------------------------------------------------------
    // convertToShares / convertToAssets
    // -----------------------------------------------------------------------

    function test_convertToShares_zeroAssetsGivesZero() public view {
        assertEq(vault.convertToShares(0), 0);
    }

    function test_convertToAssets_zeroSharesGivesZero() public view {
        assertEq(vault.convertToAssets(0), 0);
    }

    function testFuzz_convertRoundtrip_assetsFirst(uint256 assets) public view {
        assets = bound(assets, 0, 1_000_000e18);
        uint256 shares = vault.convertToShares(assets);
        uint256 back = vault.convertToAssets(shares);
        assertLe(back, assets);
    }

    // -----------------------------------------------------------------------
    // grantRole / revokeRole (OZ v5 AccessControl)
    // -----------------------------------------------------------------------

    function test_grantRole_byAdmin() public {
        vault.grantRole(vault.REWARD_DEPOSITOR_ROLE(), depositor);
        assertTrue(vault.hasRole(vault.REWARD_DEPOSITOR_ROLE(), depositor));
    }

    function test_grantRole_byNonAdmin_reverts() public {
        // OZ v5 AccessControl reverts with AccessControlUnauthorizedAccount
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                alice,
                vault.DEFAULT_ADMIN_ROLE()
            )
        );
        vault.grantRole(vault.REWARD_DEPOSITOR_ROLE(), depositor);
    }

    function test_revokeRole() public {
        vault.grantRole(vault.PAUSER_ROLE(), alice);
        vault.revokeRole(vault.PAUSER_ROLE(), alice);
        assertFalse(vault.hasRole(vault.PAUSER_ROLE(), alice));
    }

    // -----------------------------------------------------------------------
    // Multiple depositors — share proportionality
    // -----------------------------------------------------------------------

    function test_multipleDepositors_shareProportional() public {
        vm.prank(alice);
        vault.deposit(100e18, alice);

        vm.prank(bob);
        vault.deposit(100e18, bob);

        assertEq(vault.balanceOf(alice), vault.balanceOf(bob));
    }

    function test_rewardsAccrueProportionally() public {
        vm.prank(alice);
        vault.deposit(100e18, alice);
        vm.prank(bob);
        vault.deposit(100e18, bob);

        vault.grantRole(vault.REWARD_DEPOSITOR_ROLE(), admin);
        token.approve(address(vault), 200e18);
        vault.notifyRewards(admin, 200e18);

        uint256 aliceAssets = vault.convertToAssets(vault.balanceOf(alice));
        uint256 bobAssets = vault.convertToAssets(vault.balanceOf(bob));
        assertEq(aliceAssets, bobAssets);
    }

    // -----------------------------------------------------------------------
    // Reentrancy guard: normal flows don't trip it
    // -----------------------------------------------------------------------

    function test_reentrancyGuard_normalFlowNoRevert() public {
        // Use admin (address(this)) which has remaining balance after transfers in setUp
        token.approve(address(vault), type(uint256).max);
        vault.deposit(100e18, admin);
        uint256 shares = vault.balanceOf(admin);
        vault.redeem(shares, admin, admin);
        assertEq(vault.balanceOf(admin), 0);
    }
}
