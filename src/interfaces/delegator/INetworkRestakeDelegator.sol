pragma solidity 0.8.25;

import {IBaseDelegator} from "./IBaseDelegator.sol";

interface INetworkRestakeDelegator is IBaseDelegator {
    error ExceedsMaxNetworkLimit();
    error MissingRoleHolders();
    error ZeroAddressRoleHolder();
    error DuplicateRoleHolder();

    struct StakeHints {
        IBaseDelegator.StakeBaseHints baseHints;
        uint32 activeStakeHint;
        uint32 networkLimitHint;
        uint32 totalOperatorNetworkSharesHint;
        uint32 operatorNetworkSharesHint;
    }

    /**
     * @notice Initial parameters needed for a full restaking delegator deployment.
     * @param baseParams base parameters for delegators' deployment
     * @param networkLimitSetRoleHolders array of addresses of the initial NETWORK_LIMIT_SET_ROLE holders
     * @param operatorNetworkSharesSetRoleHolders array of addresses of the initial OPERATOR_NETWORK_SHARES_SET_ROLE holders
     */
    struct InitParams {
        IBaseDelegator.BaseParams baseParams;
        address[] networkLimitSetRoleHolders;
        address[] operatorNetworkSharesSetRoleHolders;
    }

    /**
     * @notice Emitted when a network's limit is set.
     * @param network address of the network
     * @param amount new network's limit (how much stake the vault curator is ready to give to the network)
     */
    event SetNetworkLimit(address indexed network, uint256 amount);

    /**
     * @notice Emitted when an operator's shares inside a network are set.
     * @param network address of the network
     * @param operator address of the operator
     * @param shares new operator's inside the network shares (what percentage,
     *               which is equal to the shares divided by the total operators' shares,
     *               of the network's stake the vault curator is ready to give to the operator)
     */
    event SetOperatorNetworkShares(address indexed network, address indexed operator, uint256 shares);

    /**
     * @notice Get a network limit setter's role.
     * @return identifier of the network limit setter role
     */
    function NETWORK_LIMIT_SET_ROLE() external view returns (bytes32);

    /**
     * @notice Get an operator-network shares setter's role.
     * @return identifier of the operator-network shares setter role
     */
    function OPERATOR_NETWORK_SHARES_SET_ROLE() external view returns (bytes32);

    /**
     * @notice Get a network's limit at a given timestamp
     *         (how much stake the vault curator is ready to give to the network).
     * @param network address of the network
     * @param timestamp time point to get the network limit at
     * @return limit of the network at the given timestamp
     */
    function networkLimitAt(address network, uint48 timestamp) external view returns (uint256);

    /**
     * @notice Get a network's limit (how much stake the vault curator is ready to give to the network).
     * @param network address of the network
     * @return limit of the network
     */
    function networkLimit(address network) external view returns (uint256);

    /**
     * @notice Get a sum of operators' shares for a network at a given timestamp.
     * @param network address of the network
     * @param timestamp time point to get the total operators' shares at
     * @return total shares of the operators for the network at the given timestamp
     */
    function totalOperatorNetworkSharesAt(address network, uint48 timestamp) external view returns (uint256);

    /**
     * @notice Get a sum of operators' shares for a network.
     * @param network address of the network
     * @return total shares of the operators for the network
     */
    function totalOperatorNetworkShares(address network) external view returns (uint256);

    /**
     * @notice Get an operator's shares for a network at a given timestamp (what percentage,
     *         which is equal to the shares divided by the total operators' shares,
     *         of the network's stake the vault curator is ready to give to the operator).
     * @param network address of the network
     * @param operator address of the operator
     * @param timestamp time point to get the operator's shares at
     * @return shares of the operator for the network at the given timestamp
     */
    function operatorNetworkSharesAt(
        address network,
        address operator,
        uint48 timestamp
    ) external view returns (uint256);

    /**
     * @notice Get an operator's shares for a network (what percentage,
     *         which is equal to the shares divided by the total operators' shares,
     *         of the network's stake the vault curator is ready to give to the operator).
     * @param network address of the network
     * @param operator address of the operator
     * @return shares of the operator for the network
     */
    function operatorNetworkShares(address network, address operator) external view returns (uint256);

    /**
     * @notice Set a network's limit (how much stake the vault curator is ready to give to the network).
     * @param network address of the network
     * @param amount new limit of the network
     * @dev Only a NETWORK_LIMIT_SET_ROLE holder can call this function.
     */
    function setNetworkLimit(address network, uint256 amount) external;

    /**
     * @notice Set an operator's shares for a network (what percentage,
     *         which is equal to the shares divided by the total operators' shares,
     *         of the network's stake the vault curator is ready to give to the operator).
     * @param network address of the network
     * @param operator address of the operator
     * @param shares new shares of the operator for the network
     * @dev Only a OPERATOR_NETWORK_SHARES_SET_ROLE holder can call this function.
     */
    function setOperatorNetworkShares(address network, address operator, uint256 shares) external;
}
