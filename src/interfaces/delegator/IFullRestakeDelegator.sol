pragma solidity 0.8.25;

import {IBaseDelegator} from "./IBaseDelegator.sol";

interface IFullRestakeDelegator is IBaseDelegator {
    error ExceedsMaxNetworkLimit();
    error MissingRoleHolders();

    /**
     * @notice Initial parameters needed for a full restaking delegator deployment.
     * @param baseParams base parameters for delegators' deployment
     * @param networkLimitSetRoleHolder address of the initial NETWORK_LIMIT_SET_ROLE holder
     * @param operatorNetworkLimitSetRoleHolder address of the initial OPERATOR_NETWORK_LIMIT_SET_ROLE holder
     */
    struct InitParams {
        IBaseDelegator.BaseParams baseParams;
        address networkLimitSetRoleHolder;
        address operatorNetworkLimitSetRoleHolder;
    }

    /**
     * @notice Emitted when a network's limit is set.
     * @param network address of the network
     * @param amount new network's limit (how much stake the vault curator is ready to give to the network)
     */
    event SetNetworkLimit(address indexed network, uint256 amount);

    /**
     * @notice Emitted when an operator's limit for a network is set.
     * @param network address of the network
     * @param operator address of the operator
     * @param amount new operator's for the network limit
     *               (how much stake the vault curator is ready to give to the operator for the network)
     */
    event SetOperatorNetworkLimit(address indexed network, address indexed operator, uint256 amount);

    /**
     * @notice Get a network limit setter's role.
     * @return identifier of the network limit setter role
     */
    function NETWORK_LIMIT_SET_ROLE() external view returns (bytes32);

    /**
     * @notice Get an operator-network limit setter's role.
     * @return identifier of the operator-network limit setter role
     */
    function OPERATOR_NETWORK_LIMIT_SET_ROLE() external view returns (bytes32);

    /**
     * @notice Get a network's limit in `duration` seconds
     *         (how much stake the vault curator is ready to give to the network).
     * @param network address of the network
     * @param duration duration to get the network's limit in
     * @return limit of the network in `duration` seconds
     */
    function networkLimitIn(address network, uint48 duration) external view returns (uint256);

    /**
     * @notice Get a network's limit (how much stake the vault curator is ready to give to the network).
     * @param network address of the network
     * @return limit of the network
     */
    function networkLimit(address network) external view returns (uint256);

    /**
     * @notice Get a sum of operators' limits for a network in `duration` seconds.
     * @param network address of the network
     * @param duration duration to get the operator-network limit in
     * @return total limit of the operators for the network in `duration` seconds
     */
    function totalOperatorNetworkLimitIn(address network, uint48 duration) external view returns (uint256);

    /**
     * @notice Get a sum of operators' limits for a network.
     * @param network address of the network
     * @return total limit of the operators for the network
     */
    function totalOperatorNetworkLimit(address network) external view returns (uint256);

    /**
     * @notice Get an operator's limit for a network in `duration` seconds
     *         (how much stake the vault curator is ready to give to the operator for the network).
     * @param network address of the network
     * @param operator address of the operator
     * @param duration duration to get the operator-network limit in
     * @return limit of the operator for the network in `duration` seconds
     */
    function operatorNetworkLimitIn(
        address network,
        address operator,
        uint48 duration
    ) external view returns (uint256);

    /**
     * @notice Get an operator's limit for a network.
     *         (how much stake the vault curator is ready to give to the operator for the network)
     * @param network address of the network
     * @param operator address of the operator
     * @return limit of the operator for the network
     */
    function operatorNetworkLimit(address network, address operator) external view returns (uint256);

    /**
     * @notice Set a network's limit (how much stake the vault curator is ready to give to the network).
     * @param network address of the network
     * @param amount new limit of the network
     * @dev Only the NETWORK_LIMIT_SET_ROLE holder can call this function.
     */
    function setNetworkLimit(address network, uint256 amount) external;

    /**
     * @notice Set an operator's limit for a network.
     *         (how much stake the vault curator is ready to give to the operator for the network)
     * @param network address of the network
     * @param operator address of the operator
     * @param amount new limit of the operator for the network
     * @dev Only the OPERATOR_NETWORK_LIMIT_SET_ROLE holder can call this function.
     */
    function setOperatorNetworkLimit(address network, address operator, uint256 amount) external;
}
