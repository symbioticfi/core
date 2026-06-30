// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IDelegatorHook
 * @notice Interface for the DelegatorHook contract.
 */
interface IDelegatorHook {
    /**
     * @notice Called when a slash happens.
     * @param subnetwork Full identifier of the subnetwork (address of the network concatenated with the uint96 identifier).
     * @param operator Address of the operator.
     * @param amount Amount of the collateral to be slashed.
     * @param captureTimestamp Time point when the stake was captured.
     * @param data Some additional data.
     */
    function onSlash(bytes32 subnetwork, address operator, uint256 amount, uint48 captureTimestamp, bytes calldata data)
        external;
}
