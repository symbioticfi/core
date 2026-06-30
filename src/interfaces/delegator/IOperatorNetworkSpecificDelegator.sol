// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IBaseDelegator} from "./IBaseDelegator.sol";

uint64 constant OPERATOR_NETWORK_SPECIFIC_DELEGATOR_TYPE = 3;

/**
 * @title IOperatorNetworkSpecificDelegator
 * @notice Interface for the OperatorNetworkSpecificDelegator contract.
 */
interface IOperatorNetworkSpecificDelegator is IBaseDelegator {
    error InvalidNetwork();
    error NotOperator();

    /**
     * @notice Hints for a stake.
     * @param baseHints Base hints.
     * @param activeStakeHint Hint for the active stake checkpoint.
     * @param maxNetworkLimitHint Hint for the maximum subnetwork limit checkpoint.
     */
    struct StakeHints {
        bytes baseHints;
        bytes activeStakeHint;
        bytes maxNetworkLimitHint;
    }

    /**
     * @notice Initial parameters needed for an operator-network-specific delegator deployment.
     * @param baseParams Base parameters for delegators' deployment.
     * @param network Address of the single network.
     * @param operator Address of the single operator.
     */
    struct InitParams {
        IBaseDelegator.BaseParams baseParams;
        address network;
        address operator;
    }

    /**
     * @notice Get the operator registry's address.
     * @return Address Of the operator registry.
     */
    function OPERATOR_REGISTRY() external view returns (address);

    /**
     * @notice Get a network the vault delegates funds to.
     * @return Address Of the network.
     */
    function network() external view returns (address);

    /**
     * @notice Get an operator managing the vault's funds.
     * @return Address Of the operator.
     */
    function operator() external view returns (address);

    /**
     * @notice Get a particular subnetwork's maximum limit at a given timestamp using a hint
     * (meaning the subnetwork is not ready to get more as a stake).
     * @param subnetwork Full identifier of the subnetwork (address of the network concatenated with the uint96 identifier).
     * @param timestamp Time point to get the maximum subnetwork limit at.
     * @param hint Hint for checkpoint index.
     * @return Maximum Limit of the subnetwork.
     */
    function maxNetworkLimitAt(bytes32 subnetwork, uint48 timestamp, bytes memory hint) external view returns (uint256);
}
