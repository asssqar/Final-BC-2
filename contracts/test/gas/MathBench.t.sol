// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {YulMath} from "../../src/libs/YulMath.sol";
import {PureMath} from "../../src/libs/PureMath.sol";

/// @notice Head-to-head gas benchmark: Yul-optimised math vs the Solidity reference impl.
/// @dev Run `forge test --match-contract MathBench --gas-report` to see the breakdown.
///      Numbers are also captured in `docs/GAS.md`.
contract MathBenchYul {
    function sqrt(uint256 x) external pure returns (uint256) {
        return YulMath.sqrt(x);
    }

    function mulDiv(uint256 a, uint256 b, uint256 d) external pure returns (uint256) {
        return YulMath.mulDiv(a, b, d);
    }
}

contract MathBenchPure {
    function sqrt(uint256 x) external pure returns (uint256) {
        return PureMath.sqrt(x);
    }

    function mulDiv(uint256 a, uint256 b, uint256 d) external pure returns (uint256) {
        return PureMath.mulDiv(a, b, d);
    }
}

contract MathBenchTest is Test {
    MathBenchYul internal yulC;
    MathBenchPure internal pureC;

    function setUp() public {
        yulC = new MathBenchYul();
        pureC = new MathBenchPure();
    }

    function test_sqrt_equivalence(uint256 x) public view {
        x = bound(x, 0, type(uint128).max);
        assertEq(yulC.sqrt(x), pureC.sqrt(x));
    }

    function test_mulDiv_equivalence(uint128 a, uint128 b, uint128 d) public view {
        if (d == 0) return;
        assertEq(yulC.mulDiv(a, b, d), pureC.mulDiv(a, b, d));
    }

    /// @notice Snapshot the per-call gas of each variant. The values are emitted as logs.
    function test_gasSnapshot() public {
        uint256 g0 = gasleft();
        yulC.sqrt(123_456_789e18);
        emit log_named_uint("yul.sqrt gas", g0 - gasleft());

        g0 = gasleft();
        pureC.sqrt(123_456_789e18);
        emit log_named_uint("pure.sqrt gas", g0 - gasleft());

        g0 = gasleft();
        yulC.mulDiv(1e18, 2e18, 3e18);
        emit log_named_uint("yul.mulDiv gas", g0 - gasleft());

        g0 = gasleft();
        pureC.mulDiv(1e18, 2e18, 3e18);
        emit log_named_uint("pure.mulDiv gas", g0 - gasleft());
    }
}
