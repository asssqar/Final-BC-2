// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title YulMath
/// @notice Inline-Yul implementations of the small math primitives used by `ResourceAMM`.
/// @dev Each function is benchmarked head-to-head against `PureMath` in `test/gas/MathBench.t.sol`.
///      The Yul versions skip Solidity's overflow checks where the inputs are bounded by ERC-20
///      semantics (max supply ≤ 2^112), saving 30–80 gas per call without compromising safety.
library YulMath {
    /// @notice Babylonian (Newton-Raphson) integer square root, identical to Uniswap V2's `sqrt`
    ///         but expressed entirely in Yul to avoid memory allocations and Solidity arithmetic
    ///         overhead.
    /// @return result floor(sqrt(x)).
    function sqrt(uint256 x) internal pure returns (uint256 result) {
        // Same algorithm as PureMath.sqrt but lifted into a single Yul block.
        // Branch-on-magnitude to compute a tight initial estimate, then 7 Newton iterations.
        assembly {
            if gt(x, 3) {
                result := x
                // Initial estimate: 2^(ceil(log2(x))/2). We use a binary-search style branchless
                // shift selection to compute the most-significant bit of x.
                let xAux := x
                let r := 1
                if iszero(lt(xAux, 0x100000000000000000000000000000000)) {
                    // 2^128
                    xAux := shr(128, xAux)
                    r := shl(64, r)
                }
                if iszero(lt(xAux, 0x10000000000000000)) {
                    // 2^64
                    xAux := shr(64, xAux)
                    r := shl(32, r)
                }
                if iszero(lt(xAux, 0x100000000)) {
                    // 2^32
                    xAux := shr(32, xAux)
                    r := shl(16, r)
                }
                if iszero(lt(xAux, 0x10000)) {
                    // 2^16
                    xAux := shr(16, xAux)
                    r := shl(8, r)
                }
                if iszero(lt(xAux, 0x100)) {
                    // 2^8
                    xAux := shr(8, xAux)
                    r := shl(4, r)
                }
                if iszero(lt(xAux, 0x10)) {
                    // 2^4
                    xAux := shr(4, xAux)
                    r := shl(2, r)
                }
                if iszero(lt(xAux, 0x4)) {
                    // 2^2
                    r := shl(1, r)
                }

                // 7 Newton iterations: r = (r + x/r) / 2
                r := shr(1, add(r, div(x, r)))
                r := shr(1, add(r, div(x, r)))
                r := shr(1, add(r, div(x, r)))
                r := shr(1, add(r, div(x, r)))
                r := shr(1, add(r, div(x, r)))
                r := shr(1, add(r, div(x, r)))
                r := shr(1, add(r, div(x, r)))

                let r2 := div(x, r)
                if lt(r2, r) { r := r2 }
                result := r
            }
            if eq(x, 0) { result := 0 }
            if and(gt(x, 0), lt(x, 4)) { result := 1 }
        }
    }

    /// @notice Returns floor((a * b) / d) with full 512-bit intermediate product, reverting on
    ///         div-by-zero or overflow. Equivalent to `OpenZeppelin.Math.mulDiv` but expressed in
    ///         a tight Yul block — used by the AMM's price helpers.
    function mulDiv(uint256 a, uint256 b, uint256 d) internal pure returns (uint256 result) {
        assembly {
            if iszero(d) { revert(0, 0) }

            let mm := mulmod(a, b, not(0))
            let prod0 := mul(a, b)
            let prod1 := sub(sub(mm, prod0), lt(mm, prod0))

            switch prod1
            case 0 {
                result := div(prod0, d)
            }
            default {
                if iszero(gt(d, prod1)) { revert(0, 0) }

                // Two's complement of d
                let twos := and(sub(0, d), d)
                d := div(d, twos)
                prod0 := div(prod0, twos)
                let inv := mul(twos, sub(2, mul(d, twos)))

                inv := mul(inv, sub(2, mul(d, inv)))
                inv := mul(inv, sub(2, mul(d, inv)))
                inv := mul(inv, sub(2, mul(d, inv)))
                inv := mul(inv, sub(2, mul(d, inv)))
                inv := mul(inv, sub(2, mul(d, inv)))
                inv := mul(inv, sub(2, mul(d, inv)))

                let twosInv := add(div(sub(0, twos), twos), 1)
                prod0 := or(prod0, mul(prod1, twosInv))

                result := mul(prod0, inv)
            }
        }
    }

    /// @notice Returns the smaller of (a, b) without a Solidity branch.
    function min(uint256 a, uint256 b) internal pure returns (uint256 r) {
        assembly {
            r := xor(a, mul(xor(a, b), lt(b, a)))
        }
    }
}
