// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface INonResolvableSlasher {
    error InvalidSlashDuration();
    error InsufficientSlash();
    error NetworkNotOptedInVault();
    error NotNetwork();
    error NotNetworkMiddleware();
    error NotOperator();
    error NotResolver();
    error NotVault();
    error OperatorNotOptedInNetwork();
    error OperatorNotOptedInVault();
    error SlashCompleted();
    error SlashPeriodEnded();
    error SlashRequestNotExist();
    error VetoPeriodEnded();
    error VetoPeriodNotEnded();

    /**
     * @notice Structure for a slash request.
     * @param network network that requested the slash
     * @param resolver resolver that can veto the slash
     * @param operator operator that could be slashed (if the request is not vetoed)
     * @param amount maximum amount of the collateral to be slashed
     * @param vetoDeadline deadline for the resolver to veto the slash (exclusively)
     * @param executeDeadline deadline to execute slash (exclusively)
     * @param completed if the slash was vetoed/executed
     */
    struct SlashRequest {
        address network;
        address resolver;
        address operator;
        uint256 amount;
        uint48 vetoDeadline;
        uint48 executeDeadline;
        bool completed;
    }

    /**
     * @notice Emitted when a slash request is created.
     * @param slashIndex index of the slash request
     * @param network network that requested the slash
     * @param resolver resolver that can veto the slash
     * @param operator operator that could be slashed (if the request is not vetoed)
     * @param slashAmount maximum amount of the collateral to be slashed
     * @param vetoDeadline deadline for the resolver to veto the slash (exclusively)
     * @param executeDeadline deadline to execute slash (exclusively)
     */
    event RequestSlash(
        uint256 indexed slashIndex,
        address indexed network,
        address resolver,
        address indexed operator,
        uint256 slashAmount,
        uint48 vetoDeadline,
        uint48 executeDeadline
    );

    /**
     * @notice Emitted when a slash request is executed.
     * @param slashIndex index of the slash request
     * @param slashedAmount amount of the collateral slashed
     */
    event ExecuteSlash(uint256 indexed slashIndex, uint256 slashedAmount);

    /**
     * @notice Emitted when a slash request is vetoed.
     * @param slashIndex index of the slash request
     */
    event VetoSlash(uint256 indexed slashIndex);

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
     * @notice Get the network middleware service's address.
     * @return address of the network middleware service
     */
    function NETWORK_MIDDLEWARE_SERVICE() external view returns (address);

    /**
     * @notice Get the network-vault opt-in service's address.
     * @return address of the network-vault opt-in service
     */
    function NETWORK_VAULT_OPT_IN_SERVICE() external view returns (address);

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
     * @notice Get the delegator address.
     * @return address of the delegator
     */
    function delegator() external view returns (address);

    /**
     * @notice Get a duration during which resolvers can veto slash requests.
     * @return duration of the veto period
     */
    function vetoDuration() external view returns (uint48);

    /**
     * @notice Get a duration during which slash requests can be executed (after the veto period).
     * @return duration of the slash period
     */
    function executeDuration() external view returns (uint48);

    /**
     * @notice Get a total number of slash requests.
     * @return total number of slash requests
     */
    function slashRequestsLength() external view returns (uint256);

    /**
     * @notice Get a particular slash request.
     * @param slashIndex index of the slash request
     * @return network network that requested the slash
     * @return resolver resolver that can veto the slash
     * @return operator operator that could be slashed (if the request is not vetoed)
     * @return amount maximum amount of the collateral to be slashed
     * @return vetoDeadline deadline for the resolver to veto the slash (exclusively)
     * @return executeDeadline deadline to execute slash (exclusively)
     * @return completed if the slash was vetoed/executed
     */
    function slashRequests(uint256 slashIndex)
        external
        view
        returns (
            address network,
            address resolver,
            address operator,
            uint256 amount,
            uint48 vetoDeadline,
            uint48 executeDeadline,
            bool completed
        );

    /**
     * @notice Get a maximum amount of collateral that can be slashed
     *         for a particular network, resolver, and operator in `duration` seconds.
     * @param network address of the network
     * @param resolver address of the resolver
     * @param operator address of the operator
     * @param duration duration to get the slashable amount in
     * @return maximum amount of the collateral that can be slashed in `duration` seconds
     */
    function slashableAmountIn(
        address network,
        address resolver,
        address operator,
        uint48 duration
    ) external view returns (uint256);

    /**
     * @notice Get a maximum amount of collateral that can be slashed for a particular network, resolver, and operator.
     * @param network address of the network
     * @param resolver address of the resolver
     * @param operator address of the operator
     * @return maximum amount of the collateral that can be slashed
     */
    function slashableAmount(address network, address resolver, address operator) external view returns (uint256);

    /**
     * @notice Get a minimum stake that a given network will be able to slash using a particular resolver
     *         for a certain operator during `duration` (if no cross-slashing).
     * @param network address of the network
     * @param resolver address of the resolver
     * @param operator address of the operator
     * @param duration duration to get the minimum slashable stake during
     * @return minimum slashable stake during `duration`
     */
    function minStakeDuring(
        address network,
        address resolver,
        address operator,
        uint48 duration
    ) external view returns (uint256);

    /**
     * @notice Request a slash using a network and a resolver for a particular operator by a given amount.
     * @param network address of the network
     * @param resolver address of the resolver
     * @param operator address of the operator
     * @param amount maximum amount of the collateral to be slashed
     * @return slashIndex index of the slash request
     * @dev Only network middleware can call this function.
     */
    function requestSlash(
        address network,
        address resolver,
        address operator,
        uint256 amount
    ) external returns (uint256 slashIndex);

    /**
     * @notice Execute a slash with a given slash index.
     * @param slashIndex index of the slash request
     * @return slashedAmount amount of the collateral slashed
     * @dev Anyone can call this function.
     */
    function executeSlash(uint256 slashIndex) external returns (uint256 slashedAmount);

    /**
     * @notice Veto a slash with a given slash index.
     * @param slashIndex index of the slash request
     * @dev Only a resolver can call this function.
     */
    function vetoSlash(uint256 slashIndex) external;
}
