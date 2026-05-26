// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IMulticallable
 * @notice Interface for contracts that support multicall.
 */
interface IMulticallable {
    /**
     * @notice Execute a batch of delegatecalls on the contract.
     * @param data Calldata items to execute.
     */
    function multicall(bytes[] calldata data) external;
}