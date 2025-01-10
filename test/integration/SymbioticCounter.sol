// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract SymbioticCounter {
    uint256 internal _count;

    function _count_Symbiotic() internal virtual returns (uint256) {
        return _count++;
    }
}
