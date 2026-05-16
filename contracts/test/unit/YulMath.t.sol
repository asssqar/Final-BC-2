// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {YulMath} from "../../src/libs/YulMath.sol";

/// @dev Wrapper that exposes YulMath internals as external calls so vm.expectRevert works.
contract YulMathWrapper {
    function sqrt(uint256 x) external pure returns (uint256) {
        return YulMath.sqrt(x);
    }

    function mulDiv(uint256 a, uint256 b, uint256 d) external pure returns (uint256) {
        return YulMath.mulDiv(a, b, d);
    }

    function min(uint256 a, uint256 b) external pure returns (uint256) {
        return YulMath.min(a, b);
    }
}

/// @title YulMathTest
/// @notice Full branch-coverage suite for YulMath.sol.
///         Uses YulMathWrapper so that vm.expectRevert works correctly
///         for assembly-level reverts inside internal library functions.
contract YulMathTest is Test {
    YulMathWrapper internal w;

    function setUp() public {
        w = new YulMathWrapper();
    }

    // -----------------------------------------------------------------------
    // sqrt — x == 0
    // -----------------------------------------------------------------------

    function test_sqrt_zero() public view {
        assertEq(w.sqrt(0), 0);
    }

    // -----------------------------------------------------------------------
    // sqrt — x in [1, 3]  (the `and(gt(x,0), lt(x,4))` branch → result 1)
    // -----------------------------------------------------------------------

    function test_sqrt_one() public view {
        assertEq(w.sqrt(1), 1);
    }

    function test_sqrt_two() public view {
        assertEq(w.sqrt(2), 1);
    }

    function test_sqrt_three() public view {
        assertEq(w.sqrt(3), 1);
    }

    // -----------------------------------------------------------------------
    // sqrt — x == 4  (first value hitting the gt(x,3) branch)
    // -----------------------------------------------------------------------

    function test_sqrt_four() public view {
        assertEq(w.sqrt(4), 2);
    }

    // -----------------------------------------------------------------------
    // sqrt — small perfect squares
    // -----------------------------------------------------------------------

    function test_sqrt_perfectSquares_small() public view {
        assertEq(w.sqrt(9), 3);
        assertEq(w.sqrt(16), 4);
        assertEq(w.sqrt(25), 5);
        assertEq(w.sqrt(100), 10);
        assertEq(w.sqrt(10_000), 100);
    }

    // -----------------------------------------------------------------------
    // sqrt — magnitude bucket: >= 0x10 (exercises shl(2,r) branch, 2^4 range)
    // -----------------------------------------------------------------------

    function test_sqrt_magnitude_2_4() public view {
        assertEq(w.sqrt(16), 4);
        assertEq(w.sqrt(15), 3);
    }

    // -----------------------------------------------------------------------
    // sqrt — magnitude bucket: >= 0x100 (exercises shl(4,r) branch, 2^8 range)
    // -----------------------------------------------------------------------

    function test_sqrt_magnitude_2_8() public view {
        assertEq(w.sqrt(256), 16);
        assertEq(w.sqrt(255), 15);
    }

    // -----------------------------------------------------------------------
    // sqrt — magnitude bucket: >= 0x10000 (exercises shl(8,r) branch, 2^16 range)
    // -----------------------------------------------------------------------

    function test_sqrt_magnitude_2_16() public view {
        assertEq(w.sqrt(65_536), 256);
        assertEq(w.sqrt(65_535), 255);
    }

    // -----------------------------------------------------------------------
    // sqrt — magnitude bucket: >= 0x100000000 (shl(16,r), 2^32 range)
    // -----------------------------------------------------------------------

    function test_sqrt_magnitude_2_32() public view {
        uint256 x = 1 << 32;
        assertEq(w.sqrt(x), 65_536);
        assertEq(w.sqrt(x - 1), 65_535);
    }

    // -----------------------------------------------------------------------
    // sqrt — magnitude bucket: >= 0x10000000000000000 (shl(32,r), 2^64 range)
    // -----------------------------------------------------------------------

    function test_sqrt_magnitude_2_64() public view {
        uint256 x = 1 << 64;
        assertEq(w.sqrt(x), 1 << 32);
        assertEq(w.sqrt(x - 1), (1 << 32) - 1);
    }

    // -----------------------------------------------------------------------
    // sqrt — magnitude bucket: >= 2^128 (shl(64,r) branch)
    // -----------------------------------------------------------------------

    function test_sqrt_magnitude_2_128() public view {
        uint256 x = 1 << 128;
        assertEq(w.sqrt(x), 1 << 64);
        uint256 y = (1 << 128) - 1;
        uint256 r = w.sqrt(y);
        assertLe(r * r, y);
        assertGt((r + 1) * (r + 1), y);
    }

    // -----------------------------------------------------------------------
    // sqrt — x == type(uint256).max  (exercises all magnitude branches)
    // -----------------------------------------------------------------------

    function test_sqrt_maxUint256() public view {
        uint256 r = w.sqrt(type(uint256).max);
        // floor(sqrt(2^256 - 1)) == 2^128 - 1
        assertEq(r, type(uint128).max);
    }

    // -----------------------------------------------------------------------
    // sqrt — floor property (fuzz)
    // -----------------------------------------------------------------------

    function test_sqrt_isFloor(uint256 x) public view {
        vm.assume(x > 0);
        uint256 r = w.sqrt(x);
        assertLe(r * r, x);
        if (r < type(uint128).max) {
            assertGt((r + 1) * (r + 1), x);
        }
    }

    // -----------------------------------------------------------------------
    // sqrt — fuzz: matches pure-Solidity Babylonian reference
    // -----------------------------------------------------------------------

    function testFuzz_sqrt_matchesReference(uint256 x) public view {
        assertEq(w.sqrt(x), _refSqrt(x));
    }

    // -----------------------------------------------------------------------
    // mulDiv — revert on d == 0
    // -----------------------------------------------------------------------

    function test_mulDiv_revertOnZeroDivisor() public {
        vm.expectRevert();
        w.mulDiv(1, 1, 0);
    }

    // -----------------------------------------------------------------------
    // mulDiv — prod1 == 0 path (product fits in 256 bits)
    // -----------------------------------------------------------------------

    function test_mulDiv_simple() public view {
        assertEq(w.mulDiv(6, 3, 2), 9);
        assertEq(w.mulDiv(1000, 1, 100), 10);
    }

    function test_mulDiv_exactDivision() public view {
        assertEq(w.mulDiv(type(uint128).max, type(uint128).max, type(uint128).max), type(uint128).max);
    }

    function test_mulDiv_truncatesDown() public view {
        assertEq(w.mulDiv(10, 1, 3), 3);
        assertEq(w.mulDiv(7, 1, 2), 3);
    }

    // -----------------------------------------------------------------------
    // mulDiv — full 512-bit path (prod1 != 0, d > prod1)
    //
    // (2^128) * (2^128) = 2^256, which wraps to 0 in EVM mul but mulmod captures
    // the high 256 bits. prod0 = 0, prod1 = 1.
    // We need d > prod1, so use d = 2^129. Result = 2^256 / 2^129 = 2^127.
    // -----------------------------------------------------------------------

    function test_mulDiv_full512Path() public view {
        uint256 a = 1 << 128;
        uint256 b = 1 << 128;
        uint256 d = 1 << 129; // d > prod1 (which is 1), so no overflow revert
        uint256 result = w.mulDiv(a, b, d);
        assertEq(result, 1 << 127);
    }

    function test_mulDiv_full512_knownValue() public view {
        assertEq(w.mulDiv(type(uint256).max, 1, 1), type(uint256).max);
    }

    // -----------------------------------------------------------------------
    // mulDiv — overflow revert when d <= prod1
    // -----------------------------------------------------------------------

    function test_mulDiv_revertOnOverflow() public {
        // (2^128) * (2^128): prod1 = 1, d = 1 → d NOT gt prod1 → revert
        vm.expectRevert();
        w.mulDiv(1 << 128, 1 << 128, 1);
    }

    // -----------------------------------------------------------------------
    // mulDiv — fuzz (prod1 == 0 path, safe inputs via uint128)
    // -----------------------------------------------------------------------

    function testFuzz_mulDiv_prod0Path(uint128 a, uint128 b, uint128 d) public view {
        vm.assume(d > 0);
        uint256 result = w.mulDiv(uint256(a), uint256(b), uint256(d));
        uint256 expected = (uint256(a) * uint256(b)) / uint256(d);
        assertEq(result, expected);
    }

    // -----------------------------------------------------------------------
    // min — basic cases
    // -----------------------------------------------------------------------

    function test_min_aLessThanB() public view {
        assertEq(w.min(1, 2), 1);
        assertEq(w.min(0, type(uint256).max), 0);
    }

    function test_min_aGreaterThanB() public view {
        assertEq(w.min(10, 3), 3);
        assertEq(w.min(type(uint256).max, 0), 0);
    }

    function test_min_equal() public view {
        assertEq(w.min(5, 5), 5);
        assertEq(w.min(0, 0), 0);
        assertEq(w.min(type(uint256).max, type(uint256).max), type(uint256).max);
    }

    function testFuzz_min_correct(uint256 a, uint256 b) public view {
        uint256 expected = a < b ? a : b;
        assertEq(w.min(a, b), expected);
    }

    // -----------------------------------------------------------------------
    // Reference sqrt (pure Solidity Babylonian — for fuzz comparison)
    // -----------------------------------------------------------------------

    function _refSqrt(uint256 x) internal pure returns (uint256 r) {
        if (x == 0) return 0;
        if (x < 4) return 1;
        r = x;
        uint256 k = x / 2 + 1;
        while (k < r) {
            r = k;
            k = (x / k + k) / 2;
        }
    }
}
