// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IVetoSlasher {
    error InvalidSlashDuration();
    error InsufficientSlash();
    error NotNetwork();
    error NotResolver();
    error SlashRequestCompleted();
    error SlashPeriodEnded();
    error SlashRequestNotExist();
    error VetoPeriodEnded();
    error VetoPeriodNotEnded();
    error InvalidShares();
    error InvalidTotalShares();
    error InvalidResolversLength();
    error InvalidResolversSetEpochsDelay();
    error ResolverAlreadySet();

    struct InitParams {
        address vault;
        uint48 vetoDuration;
        uint48 executeDuration;
        uint256 resolversSetEpochsDelay;
    }

    /**
     * @notice Structure for a slash request.
     * @param network network that requested the slash
     * @param operator operator that could be slashed (if the request is not vetoed)
     * @param amount maximum amount of the collateral to be slashed
     * @param vetoDeadline deadline for the resolver to veto the slash (exclusively)
     * @param executeDeadline deadline to execute slash (exclusively)
     * @param completed if the slash was vetoed/executed
     */
    struct SlashRequest {
        address network;
        address operator;
        uint256 amount;
        uint48 vetoDeadline;
        uint48 executeDeadline;
        uint256 vetoedShares;
        bool completed;
    }

    /**
     * @notice Emitted when a slash request is created.
     * @param slashIndex index of the slash request
     * @param network network that requested the slash
     * @param operator operator that could be slashed (if the request is not vetoed)
     * @param slashAmount maximum amount of the collateral to be slashed
     * @param vetoDeadline deadline for the resolver to veto the slash (exclusively)
     * @param executeDeadline deadline to execute slash (exclusively)
     */
    event RequestSlash(
        uint256 indexed slashIndex,
        address indexed network,
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

    event SetResolver(address indexed network, address resolver, uint256 shares);

    function SHARES_BASE() external view returns (uint256);

    function RESOLVER_SHARES_SET_ROLE() external view returns (bytes32);

    function NETWORK_REGISTRY() external view returns (address);

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
     * @return operator operator that could be slashed (if the request is not vetoed)
     * @return amount maximum amount of the collateral to be slashed
     * @return vetoDeadline deadline for the resolver to veto the slash (exclusively)
     * @return executeDeadline deadline to execute slash (exclusively)
     * @return vetoedShares amount of the shares of the request vetoed
     * @return completed if the slash was vetoed/executed
     */
    function slashRequests(uint256 slashIndex)
        external
        view
        returns (
            address network,
            address operator,
            uint256 amount,
            uint48 vetoDeadline,
            uint48 executeDeadline,
            uint256 vetoedShares,
            bool completed
        );

    function resolversSetDelay() external view returns (uint48);

    function resolverSharesAt(address network, address resolver, uint48 timestamp) external view returns (uint256);

    function resolverShares(address network, address resolver) external view returns (uint256);

    /**
     * @notice Request a slash using a network and a resolver for a particular operator by a given amount.
     * @param network address of the network
     * @param operator address of the operator
     * @param amount maximum amount of the collateral to be slashed
     * @return slashIndex index of the slash request
     * @dev Only network middleware can call this function.
     */
    function requestSlash(address network, address operator, uint256 amount) external returns (uint256 slashIndex);

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

    function setResolverShares(address resolver, uint256 shares) external;
}
