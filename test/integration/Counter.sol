// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

contract Counter {
    uint256 internal _count;

    function count() public returns (uint256) {
        return _count++;
    }
}
