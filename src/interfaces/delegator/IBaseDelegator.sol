pragma solidity 0.8.25;

interface IBaseDelegator {
    error AlreadySet();
    error NotSlasher();
    error NotNetwork();
    error NotVault();
    error TooMuchSlash();

    /**
     * @notice Base parameters needed for delegators' deployment.
     * @param defaultAdminRoleHolder address of the initial DEFAULT_ADMIN_ROLE holder
     * @param hook address of the hook contract
     * @param hookSetRoleHolder address of the initial HOOK_SET_ROLE holder
     */
    struct BaseParams {
        address defaultAdminRoleHolder;
        address hook;
        address hookSetRoleHolder;
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
     * @notice Emitted when a hook is set.
     * @param hook address of the hook
     */
    event SetHook(address indexed hook);

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

    function HOOK_SET_ROLE() external view returns (bytes32);

    /**
     * @notice Get the vault's address.
     * @return address of the vault
     */
    function vault() external view returns (address);

    /**
     * @notice Get the hook's address.
     * @return address of the hook
     * @dev The hook can have arbitrary logic under certain functions, however, it doesn't affect the stake guarantees.
     */
    function hook() external view returns (address);

    /**
     * @notice Get a particular network's maximum limit
     *         (meaning the network is not ready to get more as a stake).
     * @param network address of the network
     * @return maximum limit of the network
     */
    function maxNetworkLimit(address network) external view returns (uint256);

    /**
     * @notice Get a stake that a given network could be able to slash
     *         for a certain operator at a given timestamp until the end of the consequent epoch (if no cross-slashing and no slashings by the network).
     * @param network address of the network
     * @param operator address of the operator
     * @param timestamp time point to capture the stake at
     * @return slashable stake at the given timestamp until the end of the consequent epoch
     * @dev Warning: it is not safe to use timestamp >= current one for the stake capturing, as it can change later.
     */
    function stakeAt(address network, address operator, uint48 timestamp) external view returns (uint256);

    /**
     * @notice Get a stake that a given network will be able to slash
     *         for a certain operator until the end of the next epoch (if no cross-slashing and no slashings by the network).
     * @param network address of the network
     * @param operator address of the operator
     * @return slashable stake until the end of the next epoch
     * @dev Warning: this function is not safe to use for the stake capturing, as it can change by the end of the block.
     */
    function stake(address network, address operator) external view returns (uint256);

    /**
     * @notice Set a maximum limit for a network (how much stake the network is ready to get).
     * @param amount new maximum network's limit
     * @dev Only a network can call this function.
     */
    function setMaxNetworkLimit(uint256 amount) external;

    /**
     * @notice Set a new hook.
     * @param hook address of the hook
     * @dev Only a HOOK_SET_ROLE holder can call this function.
     *      The hook can have arbitrary logic under certain functions, however, it doesn't affect the stake guarantees.
     */
    function setHook(address hook) external;

    /**
     * @notice Called when a slash happens.
     * @param network address of the network
     * @param operator address of the operator
     * @param slashedAmount amount of the collateral slashed
     * @param captureTimestamp time point when the stake was captured
     * @dev Only the vault's slasher can call this function.
     */
    function onSlash(address network, address operator, uint256 slashedAmount, uint48 captureTimestamp) external;
}
