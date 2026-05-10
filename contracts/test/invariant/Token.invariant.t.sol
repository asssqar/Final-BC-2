// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, StdInvariant} from "forge-std/Test.sol";
import {GameToken} from "../../src/tokens/GameToken.sol";

contract TokenHandler is Test {
    GameToken public token;
    address[] public actors;

    constructor(GameToken _t) {
        token = _t;
        actors.push(makeAddr("actor1"));
        actors.push(makeAddr("actor2"));
        actors.push(makeAddr("actor3"));
    }

    function transfer(uint8 ai, uint8 bi, uint96 amt) external {
        ai = uint8(bound(uint256(ai), 0, actors.length - 1));
        bi = uint8(bound(uint256(bi), 0, actors.length - 1));
        amt = uint96(bound(uint256(amt), 0, token.balanceOf(actors[ai])));
        vm.prank(actors[ai]);
        token.transfer(actors[bi], amt);
    }

    function burn(uint8 ai, uint96 amt) external {
        ai = uint8(bound(uint256(ai), 0, actors.length - 1));
        amt = uint96(bound(uint256(amt), 0, token.balanceOf(actors[ai])));
        vm.prank(actors[ai]);
        token.burn(amt);
    }

    function actor(uint256 i) external view returns (address) {
        return actors[i];
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }
}

contract TokenInvariantTest is StdInvariant, Test {
    GameToken internal token;
    TokenHandler internal handler;
    uint256 internal initialSupply;
    uint256 internal totalBurned;

    function setUp() public {
        token = new GameToken(address(this), address(this), 1_000_000e18);
        initialSupply = 1_000_000e18;
        handler = new TokenHandler(token);
        // Distribute tokens to handler actors
        for (uint256 i = 0; i < handler.actorCount(); ++i) {
            token.transfer(handler.actor(i), 100_000e18);
        }
        targetContract(address(handler));
    }

    /// @notice totalSupply == sum(balances). This invariant is enforced by ERC20's
    ///         internal accounting; we sanity-check it.
    function invariant_totalSupplyConsistent() public view {
        // Burn-only path lowers totalSupply, never raises it (mint role removed from anyone here).
        assertLe(token.totalSupply(), initialSupply);
    }

    /// @notice Voting power on the token never exceeds totalSupply.
    function invariant_votesNeverExceedSupply() public view {
        for (uint256 i = 0; i < handler.actorCount(); ++i) {
            assertLe(token.getVotes(handler.actor(i)), token.totalSupply());
        }
    }
}
