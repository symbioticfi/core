pragma solidity 0.8.25;

interface IBaseDelegator {
    error AlreadySet();
    error NotSlasher();
    error NotNetwork();
    error NotVault();

    struct BaseParams {
        address defaultAdminRoleHolder;
    }

    /**
     * @notice Emitted when a network's maximum limit is set.
     * @param network address of the network
     * @param amount new maximum network's limit (how much stake the network is ready to get)
     */
    event SetMaxNetworkLimit(address indexed network, uint256 amount);

    /**
     * @notice Emitted when a slash happened.
     * @param network address of the network
     * @param operator address of the operator
     * @param slashedAmount amount of the collateral slashed
     */
    event OnSlash(address indexed network, address indexed operator, uint256 slashedAmount);

    /**
     * @notice Get a version of the delegator (different versions mean different interfaces).
     * @return version of the delegator
     * @dev Must return 1 for this one.
     */
    function VERSION() external view returns (uint64);

    /**
     * @notice Get the network registry's address.
     * @return address of the network registry
     */
    function NETWORK_REGISTRY() external view returns (address);

    /**
     * @notice Get the vault factory's address.
     * @return address of the vault factory
     */
    function VAULT_FACTORY() external view returns (address);

    /**
     * @notice Get the operator-vault opt-in service's address.
     * @return address of the operator-vault opt-in service
     */
    function OPERATOR_VAULT_OPT_IN_SERVICE() external view returns (address);

    /**
     * @notice Get the operator-network opt-in service's address.
     * @return address of the operator-network opt-in service
     */
    function OPERATOR_NETWORK_OPT_IN_SERVICE() external view returns (address);

    /**
     * @notice Get the vault's address.
     * @return address of the vault
     */
    function vault() external view returns (address);

    /**
     * @notice Get a particular network's maximum limit
     *         (meaning the network is not ready to get more as a stake).
     * @param network address of the network
     * @return maximum limit of the network
     */
    function maxNetworkLimit(address network) external view returns (uint256);

    /**
     * @notice Get a maximum amount of collateral that can be slashed
     *         by a particular network in `duration` seconds.
     * @param network address of the network
     * @param duration duration to get the slashable amount in
     * @return maximum amount of the collateral that can be slashed by the network in `duration` seconds
     */
    function networkStakeIn(address network, uint48 duration) external view returns (uint256);

    /**
     * @notice Get a maximum amount of collateral that can be slashed
     *         by a particular network.
     * @param network address of the network
     * @return maximum amount of the collateral that can be slashed by the network
     */
    function networkStake(address network) external view returns (uint256);

    /**
     * @notice Get a maximum amount of collateral that can be slashed
     *         for a particular network and operator in `duration` seconds.
     * @param network address of the network
     * @param operator address of the operator
     * @param duration duration to get the slashable amount in
     * @return maximum amount of the collateral that can be slashed by the network for the operator in `duration` seconds
     */
    function operatorNetworkStakeIn(
        address network,
        address operator,
        uint48 duration
    ) external view returns (uint256);

    /**
     * @notice Get a maximum amount of collateral that can be slashed for a particular network, and operator.
     * @param network address of the network
     * @param operator address of the operator
     * @return maximum amount of the collateral that can be slashed by the network for the operator
     */
    function operatorNetworkStake(address network, address operator) external view returns (uint256);

    /**
     * @notice Get a minimum stake that a given network will be able to slash
     *         for a certain operator during `duration` (if no cross-slashing and no slashings by the network).
     * @param network address of the network
     * @param operator address of the operator
     * @param duration duration to get the minimum slashable stake during
     * @return minimum slashable stake during `duration`
     */
    function minOperatorNetworkStakeDuring(
        address network,
        address operator,
        uint48 duration
    ) external view returns (uint256);

    /**
     * @notice Set a maximum limit for a network (how much stake the network is ready to get).
     * @param amount new maximum network's limit
     * @dev Only a network can call this function.
     */
    function setMaxNetworkLimit(uint256 amount) external;

    /**
     * @notice Called when a slash happened.
     * @param network address of the network
     * @param operator address of the operator
     * @param slashedAmount amount of the collateral slashed
     * @dev Only the vault's slasher can call this function.
     */
    function onSlash(address network, address operator, uint256 slashedAmount) external;
}
