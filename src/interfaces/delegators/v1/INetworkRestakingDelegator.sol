pragma solidity 0.8.25;

import {IDelegator} from "./IDelegator.sol";

interface INetworkRestakingDelegator is IDelegator {
    error ExceedsMaxNetworkResolverLimit();
    error AlreadySet();
    error NotSlasher();
    error NotNetwork();
    error NotVault();

    struct InitParams {
        address vault;
    }

    /**
     * @notice Structure for a slashing limit.
     * @param amount amount of the collateral that can be slashed
     */
    struct Limit {
        uint256 amount;
    }

    /**
     * @notice Structure for a slashing limit that will be set in the future (if a new limit won't be set).
     * @param amount amount of the collateral that can be slashed
     * @param timestamp timestamp when the limit will be set
     */
    struct DelayedLimit {
        uint256 amount;
        uint48 timestamp;
    }

    /**
     * @notice Emitted when a maximum network-resolver limit is set.
     * @param network address of the network
     * @param resolver address of the resolver
     * @param amount maximum network-resolver limit that can be set
     */
    event SetMaxNetworkResolverLimit(
        address indexed network, address indexed resolver, uint256 amount
    );

    /**
     * @notice Emitted when a network-resolver limit is set.
     * @param network address of the network
     * @param resolver address of the resolver
     * @param amount maximum amount of the collateral that can be slashed
     */
    event SetNetworkResolverLimit(
        address indexed network, address indexed resolver, uint256 amount
    );

    /**
     * @notice Emitted when an operator-network limit is set.
     * @param operator address of the operator
     * @param network address of the network
     * @param amount maximum amount of the collateral that can be slashed
     */
    event SetOperatorNetworkLimit(
        address indexed operator, address indexed network, uint256 amount
    );

    /**
     * @notice Get the network registry's address.
     * @return address of the network registry
     */
    function NETWORK_REGISTRY() external view returns (address);

    /**
     * @notice Get the network-resolver limit setter's role.
     */
    function NETWORK_RESOLVER_LIMIT_SET_ROLE() external view returns (bytes32);

    /**
     * @notice Get the operator-network limit setter's role.
     */
    function OPERATOR_NETWORK_LIMIT_SET_ROLE() external view returns (bytes32);

    /**
     * @notice Get the vault factory's address.
     * @return address of the vault factory
     */
    function VAULT_FACTORY() external view returns (address);

    /**
     * @notice Get a maximum network-resolver limit for a particular network and resolver.
     * @param network address of the network
     * @param resolver address of the resolver
     * @return maximum network-resolver limit
     */
    function maxNetworkResolverLimit(
        address network,
        address resolver
    ) external view returns (uint256);

    /**
     * @notice Get the next network-resolver limit for a particular network and resolver.
     * @param network address of the network
     * @param resolver address of the resolver
     * @return next network-resolver limit
     * @return timestamp when the limit will be set
     */
    function nextNetworkResolverLimit(
        address network,
        address resolver
    ) external view returns (uint256, uint48);

    /**
     * @notice Get the next operator-network limit for a particular operator and network.
     * @param operator address of the operator
     * @param network address of the network
     * @return next operator-network limit
     * @return timestamp when the limit will be set
     */
    function nextOperatorNetworkLimit(
        address operator,
        address network
    ) external view returns (uint256, uint48);

    /**
     * @notice Set a maximum network-resolver limit.
     * @param resolver address of the resolver
     * @param amount maximum network-resolver limit that can be set
     * @dev Only a network can call this function.
     */
    function setMaxNetworkResolverLimit(address resolver, uint256 amount) external;

    /**
     * @notice Set a network-resolver limit for a particular network and resolver.
     * @param network address of the network
     * @param resolver address of the resolver
     * @param amount new maximum amount of the collateral that can be slashed
     * @dev Only the NETWORK_RESOLVER_LIMIT_SET_ROLE holder can call this function.
     */
    function setNetworkResolverLimit(address network, address resolver, uint256 amount) external;

    /**
     * @notice Set an operator-network limit for a particular operator and network.
     * @param operator address of the operator
     * @param network address of the network
     * @param amount new maximum amount of the collateral that can be slashed
     * @dev Only the OPERATOR_NETWORK_LIMIT_SET_ROLE holder can call this function.
     */
    function setOperatorNetworkLimit(address operator, address network, uint256 amount) external;
}
