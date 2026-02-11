// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IBaseDelegator} from "./IBaseDelegator.sol";

uint64 constant NETWORK_RESTAKE_DELEGATOR_TYPE = 0;

/**
 * @title INetworkRestakeDelegator
 * @notice Interface for the NetworkRestakeDelegator contract.
 */
interface INetworkRestakeDelegator is IBaseDelegator {
    error DuplicateRoleHolder();
    error ExceedsMaxNetworkLimit();
    error MissingRoleHolders();
    error ZeroAddressRoleHolder();

    /**
     * @notice Hints for a stake.
     * @param baseHints Base hints.
     * @param activeStakeHint Hint for the active stake checkpoint.
     * @param networkLimitHint Hint for the subnetwork limit checkpoint.
     * @param totalOperatorNetworkSharesHint Hint for the total operator-subnetwork shares checkpoint.
     * @param operatorNetworkSharesHint Hint for the operator-subnetwork shares checkpoint.
     */
    struct StakeHints {
        bytes baseHints;
        bytes activeStakeHint;
        bytes networkLimitHint;
        bytes totalOperatorNetworkSharesHint;
        bytes operatorNetworkSharesHint;
    }

    /**
     * @notice Initial parameters needed for a full restaking delegator deployment.
     * @param baseParams Base parameters for delegators' deployment.
     * @param networkLimitSetRoleHolders Array of addresses of the initial NETWORK_LIMIT_SET_ROLE holders.
     * @param operatorNetworkSharesSetRoleHolders Array of addresses of the initial OPERATOR_NETWORK_SHARES_SET_ROLE holders.
     */
    struct InitParams {
        IBaseDelegator.BaseParams baseParams;
        address[] networkLimitSetRoleHolders;
        address[] operatorNetworkSharesSetRoleHolders;
    }

    /**
     * @notice Emitted when a subnetwork's limit is set.
     * @param subnetwork Full identifier of the subnetwork (address of the network concatenated with the uint96 identifier).
     * @param amount New subnetwork's limit (how much stake the vault curator is ready to give to the subnetwork).
     */
    event SetNetworkLimit(bytes32 indexed subnetwork, uint256 amount);

    /**
     * @notice Emitted when an operator's shares inside a subnetwork are set.
     * @param subnetwork Full identifier of the subnetwork (address of the network concatenated with the uint96 identifier).
     * @param operator Address of the operator.
     * @param shares New operator's shares inside the subnetwork (what percentage,
     * which is equal to the shares divided by the total operators' shares,
     * of the subnetwork's stake the vault curator is ready to give to the operator).
     */
    event SetOperatorNetworkShares(bytes32 indexed subnetwork, address indexed operator, uint256 shares);

    /**
     * @notice Get a subnetwork limit setter's role.
     * @return Identifier Of the subnetwork limit setter role.
     */
    function NETWORK_LIMIT_SET_ROLE() external view returns (bytes32);

    /**
     * @notice Get an operator-subnetwork shares setter's role.
     * @return Identifier Of the operator-subnetwork shares setter role.
     */
    function OPERATOR_NETWORK_SHARES_SET_ROLE() external view returns (bytes32);

    /**
     * @notice Get a subnetwork's limit at a given timestamp using a hint
     * (how much stake the vault curator is ready to give to the subnetwork).
     * @param subnetwork Full identifier of the subnetwork (address of the network concatenated with the uint96 identifier).
     * @param timestamp Time point to get the subnetwork limit at.
     * @param hint Hint for checkpoint index.
     * @return Limit Of the subnetwork at the given timestamp.
     */
    function networkLimitAt(bytes32 subnetwork, uint48 timestamp, bytes memory hint) external view returns (uint256);

    /**
     * @notice Get a subnetwork's limit (how much stake the vault curator is ready to give to the subnetwork).
     * @param subnetwork Full identifier of the subnetwork (address of the network concatenated with the uint96 identifier).
     * @return Limit Of the subnetwork.
     */
    function networkLimit(bytes32 subnetwork) external view returns (uint256);

    /**
     * @notice Get a sum of operators' shares for a subnetwork at a given timestamp using a hint.
     * @param subnetwork Full identifier of the subnetwork (address of the network concatenated with the uint96 identifier).
     * @param timestamp Time point to get the total operators' shares at.
     * @param hint Hint for checkpoint index.
     * @return Total Shares of the operators for the subnetwork at the given timestamp.
     */
    function totalOperatorNetworkSharesAt(bytes32 subnetwork, uint48 timestamp, bytes memory hint)
        external
        view
        returns (uint256);

    /**
     * @notice Get a sum of operators' shares for a subnetwork.
     * @param subnetwork Full identifier of the subnetwork (address of the network concatenated with the uint96 identifier).
     * @return Total Shares of the operators for the subnetwork.
     */
    function totalOperatorNetworkShares(bytes32 subnetwork) external view returns (uint256);

    /**
     * @notice Get an operator's shares for a subnetwork at a given timestamp using a hint (what percentage,
     * which is equal to the shares divided by the total operators' shares,
     * of the subnetwork's stake the vault curator is ready to give to the operator).
     * @param subnetwork Full identifier of the subnetwork (address of the network concatenated with the uint96 identifier).
     * @param operator Address of the operator.
     * @param timestamp Time point to get the operator's shares at.
     * @param hint Hint for checkpoint index.
     * @return Shares Of the operator for the subnetwork at the given timestamp.
     */
    function operatorNetworkSharesAt(bytes32 subnetwork, address operator, uint48 timestamp, bytes memory hint)
        external
        view
        returns (uint256);

    /**
     * @notice Get an operator's shares for a subnetwork (what percentage,
     * which is equal to the shares divided by the total operators' shares,
     * of the subnetwork's stake the vault curator is ready to give to the operator).
     * @param subnetwork Full identifier of the subnetwork (address of the network concatenated with the uint96 identifier).
     * @param operator Address of the operator.
     * @return Shares Of the operator for the subnetwork.
     */
    function operatorNetworkShares(bytes32 subnetwork, address operator) external view returns (uint256);

    /**
     * @notice Set a subnetwork's limit (how much stake the vault curator is ready to give to the subnetwork).
     * @param subnetwork Full identifier of the subnetwork (address of the network concatenated with the uint96 identifier).
     * @param amount New limit of the subnetwork.
     * @dev Only a NETWORK_LIMIT_SET_ROLE holder can call this function.
     */
    function setNetworkLimit(bytes32 subnetwork, uint256 amount) external;

    /**
     * @notice Set an operator's shares for a subnetwork (what percentage,
     * which is equal to the shares divided by the total operators' shares,
     * of the subnetwork's stake the vault curator is ready to give to the operator).
     * @param subnetwork Full identifier of the subnetwork (address of the network concatenated with the uint96 identifier).
     * @param operator Address of the operator.
     * @param shares New shares of the operator for the subnetwork.
     * @dev Only an OPERATOR_NETWORK_SHARES_SET_ROLE holder can call this function.
     */
    function setOperatorNetworkShares(bytes32 subnetwork, address operator, uint256 shares) external;
}
