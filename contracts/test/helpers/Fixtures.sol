// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {GameToken} from "../../src/tokens/GameToken.sol";
import {GameItems} from "../../src/tokens/GameItems.sol";
import {ResourceAMM} from "../../src/amm/ResourceAMM.sol";
import {YieldVault} from "../../src/vaults/YieldVault.sol";
import {RentalVault} from "../../src/vaults/RentalVault.sol";
import {PriceOracle} from "../../src/oracles/PriceOracle.sol";
import {MockAggregator} from "../../src/oracles/MockAggregator.sol";
import {ItemFactory} from "../../src/factory/ItemFactory.sol";
import {GameGovernor} from "../../src/governance/GameGovernor.sol";

/// @dev Common deployment fixture used by every unit test. Mirrors the production deployment but
///      keeps `admin` as a single address for convenience.
abstract contract Fixtures is Test {
    address internal admin = makeAddr("admin");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    GameToken internal token;
    GameToken internal wood;
    GameToken internal iron;
    GameItems internal items;
    GameItems internal itemsImpl;
    ResourceAMM internal amm;
    YieldVault internal vault;
    RentalVault internal rental;
    PriceOracle internal oracle;
    MockAggregator internal feed;
    ItemFactory internal factory;
    GameGovernor internal governor;
    TimelockController internal timelock;

    function _deployAll() internal {
        vm.startPrank(admin);
        token = new GameToken(admin, admin, 10_000_000e18);
        wood = new GameToken(admin, admin, 1_000_000e18);
        iron = new GameToken(admin, admin, 1_000_000e18);

        // GameItems UUPS proxy
        itemsImpl = new GameItems();
        bytes memory data = abi.encodeCall(GameItems.initialize, (admin, "ipfs://test/{id}.json"));
        ERC1967Proxy proxy = new ERC1967Proxy(address(itemsImpl), data);
        items = GameItems(address(proxy));
        items.grantRole(items.MINTER_ROLE(), admin);

        // AMM
        amm = new ResourceAMM(IERC20(address(wood)), IERC20(address(iron)));

        // Vaults
        vault = new YieldVault(IERC20(address(token)), admin);
        rental = new RentalVault(admin, address(vault));

        // Oracle (mock feed)
        feed = new MockAggregator(2_000e8, 8);
        oracle = new PriceOracle(admin);
        oracle.setFeed(address(token), address(feed), 1 hours);

        factory = new ItemFactory(admin);

        // Governor + Timelock
        address[] memory empty = new address[](0);
        timelock = new TimelockController(2 days, empty, empty, admin);
        governor = new GameGovernor(IVotes(address(token)), timelock);
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));

        vm.stopPrank();
    }

    function _seedAlice(uint256 amount) internal {
        vm.prank(admin);
        token.transfer(alice, amount);
    }

    function _seedAMM(uint256 wAmt, uint256 iAmt) internal {
        vm.startPrank(admin);
        wood.approve(address(amm), wAmt);
        iron.approve(address(amm), iAmt);
        amm.addLiquidity(wAmt, iAmt, 0, 0, admin);
        vm.stopPrank();
    }
}
