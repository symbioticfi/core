// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IBurner
 * @notice Interface for the Burner contract.
 */
interface IBurner {
    /**
     * @notice Called when a slash happens.
     * @param subnetwork Full identifier of the subnetwork (address of the network concatenated with the uint96 identifier).
     * @param operator Address of the operator.
     * @param amount Virtual amount of the collateral slashed.
     * @param captureTimestamp Time point when the stake was captured.
     */
    function onSlash(bytes32 subnetwork, address operator, uint256 amount, uint48 captureTimestamp) external;
}
