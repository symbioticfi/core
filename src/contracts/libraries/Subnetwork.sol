// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Subnetwork
 * @notice Library implementing a subnetwork identifier encoding and parsing helper set.
 */
library Subnetwork {
    function subnetwork(address network_, uint96 identifier_) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(network_)) << 96 | identifier_);
    }

    function network(bytes32 subnetwork_) internal pure returns (address) {
        return address(uint160(uint256(subnetwork_ >> 96)));
    }

    function identifier(bytes32 subnetwork_) internal pure returns (uint96) {
        return uint96(uint256(subnetwork_));
    }
}
