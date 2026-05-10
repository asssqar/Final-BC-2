// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {GameToken} from "../src/tokens/GameToken.sol";
import {GameItems} from "../src/tokens/GameItems.sol";
import {GameGovernor} from "../src/governance/GameGovernor.sol";

/// @title PostDeployVerify
/// @notice Reads `deployments/<chainId>.json` and asserts the security invariants required by
///         §3.2 + §7. Failure of any check reverts the script.
contract PostDeployVerify is Script {
    function run() external {
        string memory chainId = vm.toString(block.chainid);
        string memory path = string.concat("./deployments/", chainId, ".json");
        string memory raw = vm.readFile(path);

        address timelock = vm.parseJsonAddress(raw, ".timelock");
        address governor = vm.parseJsonAddress(raw, ".governor");
        address proxy = vm.parseJsonAddress(raw, ".gameItemsProxy");
        address token = vm.parseJsonAddress(raw, ".gameToken");
        address deployer = vm.envAddress("DEPLOYER_ADDRESS");

        TimelockController tl = TimelockController(payable(timelock));
        require(tl.getMinDelay() == 2 days, "verify: timelock delay");
        require(tl.hasRole(tl.PROPOSER_ROLE(), governor), "verify: governor proposer");
        require(tl.hasRole(tl.EXECUTOR_ROLE(), address(0)), "verify: anyone can execute");
        require(!tl.hasRole(tl.DEFAULT_ADMIN_ROLE(), deployer), "verify: deployer admin removed from timelock");

        GameGovernor g = GameGovernor(payable(governor));
        require(g.votingDelay() == 1 days, "verify: voting delay");
        require(g.votingPeriod() == 1 weeks, "verify: voting period");
        require(g.quorumNumerator() == 4, "verify: quorum 4%");

        GameItems items = GameItems(proxy);
        require(items.hasRole(items.DEFAULT_ADMIN_ROLE(), timelock), "verify: items admin");
        require(items.hasRole(items.UPGRADER_ROLE(), timelock), "verify: items upgrader");
        require(!items.hasRole(items.UPGRADER_ROLE(), deployer), "verify: deployer upgrader removed");
        require(!items.hasRole(items.DEFAULT_ADMIN_ROLE(), deployer), "verify: deployer items admin removed");

        GameToken t = GameToken(token);
        require(t.hasRole(t.DEFAULT_ADMIN_ROLE(), timelock), "verify: token admin");
        require(!t.hasRole(t.MINTER_ROLE(), deployer), "verify: deployer minter removed");

        console2.log(unicode"PostDeployVerify ✓ — all invariants hold");
    }
}
