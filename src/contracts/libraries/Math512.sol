// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library Math512 {
    error AddOverflow();

    /**
     * @dev Add 512-bit and 256-bit numbers.
     * @param a The 512-bit number.
     * @param b The 256-bit number.
     * @return r The 512-bit sum of the two numbers.
     */
    function add(uint256[2] memory a, uint256 b) internal pure returns (uint256[2] memory r) {
        assembly ("memory-safe") {
            let aLow := mload(add(a, 0x20))
            let sum := add(aLow, b)
            mstore(add(r, 0x20), sum)
            let aHigh := mload(a)
            mstore(r, add(gt(aLow, sum), aHigh))
            if lt(mload(r), aHigh) {
                mstore(0x00, 0xa7f965e3) // `AddOverflow()`.
                revert(0x1c, 0x04)
            }
        }
    }

    /**
     * @dev Subtract 512-bit number from 512-bit number.
     * @param a The 512-bit number.
     * @param b The 512-bit number.
     * @return r The 256-bit difference of the two numbers.
     * @dev Assumes a >= b.
     */
    function sub(uint256[2] memory a, uint256[2] memory b) internal pure returns (uint256 r) {
        assembly ("memory-safe") {
            r := sub(mload(add(a, 0x20)), mload(add(b, 0x20)))
        }
    }
}
