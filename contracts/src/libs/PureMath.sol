// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title PureMath
/// @notice Pure-Solidity counterparts to `YulMath` used as a baseline in the gas benchmark.
library PureMath {
    /// @notice Floor integer square root via Newton's method (Solidity reference impl).
    function sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        // Initial estimate via floor(log2(x)) shift, same as YulMath but Solidity-side.
        uint256 r = x;
        uint256 t = x;
        if (t >= 1 << 128) {
            t >>= 128;
            r = 1 << 64;
        } else {
            r = 1;
        }
        if (t >= 1 << 64) {
            t >>= 64;
            r <<= 32;
        }
        if (t >= 1 << 32) {
            t >>= 32;
            r <<= 16;
        }
        if (t >= 1 << 16) {
            t >>= 16;
            r <<= 8;
        }
        if (t >= 1 << 8) {
            t >>= 8;
            r <<= 4;
        }
        if (t >= 1 << 4) {
            t >>= 4;
            r <<= 2;
        }
        if (t >= 1 << 2) r <<= 1;

        unchecked {
            r = (r + x / r) >> 1;
            r = (r + x / r) >> 1;
            r = (r + x / r) >> 1;
            r = (r + x / r) >> 1;
            r = (r + x / r) >> 1;
            r = (r + x / r) >> 1;
            r = (r + x / r) >> 1;
            uint256 r2 = x / r;
            return r2 < r ? r2 : r;
        }
    }

    function mulDiv(uint256 a, uint256 b, uint256 d) internal pure returns (uint256) {
        return Math.mulDiv(a, b, d);
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
