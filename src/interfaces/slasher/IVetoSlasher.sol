// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

interface IVetoSlasher {
    error AlreadyVetoed();
    error InsufficientSlash();
    error InvalidCaptureTimestamp();
    error InvalidResolverSetEpochsDelay();
    error InvalidShares();
    error InvalidVetoDuration();
    error NotNetwork();
    error NotResolver();
    error SlashPeriodEnded();
    error SlashRequestCompleted();
    error SlashRequestNotExist();
    error VaultNotInitialized();
    error VetoPeriodEnded();
    error VetoPeriodNotEnded();

    /**
     * @notice Initial parameters needed for a slasher deployment.
     * @param vetoDuration duration of the veto period for a slash request
     * @param resolverSetEpochsDelay delay in epochs for a network to update resolvers' shares
     */
    struct InitParams {
        uint48 vetoDuration;
        uint256 resolverSetEpochsDelay;
    }

    /**
     * @notice Structure for a slash request.
     * @param network network that requested the slash
     * @param operator operator that could be slashed (if the request is not vetoed)
     * @param amount maximum amount of the collateral to be slashed
     * @param captureTimestamp time point when the stake was captured
     * @param vetoDeadline deadline for the resolver to veto the slash (exclusively)
     * @param completed if the slash was vetoed/executed
     */
    struct SlashRequest {
        address network;
        address operator;
        uint256 amount;
        uint48 captureTimestamp;
        uint48 vetoDeadline;
        uint256 vetoedShares;
        bool completed;
    }

    /**
     * @notice Hints for a slash request.
     * @param slashableStakeHints hints for the slashable stake checkpoints
     */
    struct RequestSlashHints {
        bytes slashableStakeHints;
    }

    /**
     * @notice Hints for a slash execute.
     * @param slashableStakeHints hints for the slashable stake checkpoints
     * @param onSlashHints hints for the on-slash checkpoints
     */
    struct ExecuteSlashHints {
        bytes slashableStakeHints;
        bytes onSlashHints;
    }

    /**
     * @notice Hints for a slash veto.
     * @param resolverSharesHint hint for the resolver's shares checkpoint
     */
    struct VetoSlashHints {
        bytes resolverSharesHint;
    }

    /**
     * @notice Hints for a resolver shares set.
     * @param resolverSharesHint hint for the resolver's shares checkpoint
     */
    struct SetResolverSharesHints {
        bytes resolverSharesHint;
    }

    /**
     * @notice Emitted when a slash request is created.
     * @param slashIndex index of the slash request
     * @param network network that requested the slash
     * @param operator operator that could be slashed (if the request is not vetoed)
     * @param slashAmount maximum amount of the collateral to be slashed
     * @param captureTimestamp time point when the stake was captured
     * @param vetoDeadline deadline for the resolver to veto the slash (exclusively)
     */
    event RequestSlash(
        uint256 indexed slashIndex,
        address indexed network,
        address indexed operator,
        uint256 slashAmount,
        uint48 captureTimestamp,
        uint48 vetoDeadline
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
     * @param resolver address of the resolver that vetoed the slash
     * @param vetoedShares amount of the shares of the request vetoed
     */
    event VetoSlash(uint256 indexed slashIndex, address indexed resolver, uint256 vetoedShares);

    /**
     * @notice Emitted when a resolver's shares are set.
     * @param network address of the network
     * @param resolver address of the resolver
     * @param shares amount of the shares set
     */
    event SetResolver(address indexed network, address resolver, uint256 shares);

    /**
     * @notice Get a maximum amount of shares that can be set for a resolver (= 100%).
     * @return maximum amount of resolver's shares
     */
    function SHARES_BASE() external view returns (uint256);

    /**
     * @notice Get the network registry's address.
     * @return address of the network registry
     */
    function NETWORK_REGISTRY() external view returns (address);

    /**
     * @notice Get a duration during which resolvers can veto slash requests.
     * @return duration of the veto period
     */
    function vetoDuration() external view returns (uint48);

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
     * @return captureTimestamp time point when the stake was captured
     * @return vetoDeadline deadline for the resolver to veto the slash (exclusively)
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
            uint48 captureTimestamp,
            uint48 vetoDeadline,
            uint256 vetoedShares,
            bool completed
        );

    /**
     * @notice Get a delay for networks in epochs to update resolvers' shares.
     * @return updating resolvers' shares delay in epochs
     */
    function resolverSetEpochsDelay() external view returns (uint256);

    /**
     * @notice Get a resolver's shares at a particular timestamp using a hint.
     * @param network address of the network
     * @param resolver address of the resolver
     * @param timestamp timestamp to get the shares at
     * @param hints hints for the checkpoint index
     * @return amount of the resolver's shares
     */
    function resolverSharesAt(
        address network,
        address resolver,
        uint48 timestamp,
        bytes memory hints
    ) external view returns (uint256);

    /**
     * @notice Get a resolver's shares using a hint.
     * @param network address of the network
     * @param resolver address of the resolver
     * @param hint hint for the checkpoint index
     * @return amount of the resolver's shares
     */
    function resolverShares(address network, address resolver, bytes memory hint) external view returns (uint256);

    /**
     * @notice Get if a resolver has vetoed a particular slash request.
     * @param resolver address of the resolver
     * @param slashIndex index of the slash request
     * @return if the resolver has vetoed the slash request
     */
    function hasVetoed(address resolver, uint256 slashIndex) external view returns (bool);

    /**
     * @notice Request a slash using a network and a resolver for a particular operator by a given amount using hints.
     * @param network address of the network
     * @param operator address of the operator
     * @param amount maximum amount of the collateral to be slashed
     * @param captureTimestamp time point when the stake was captured
     * @param hints hints for checkpoints' indexes
     * @return slashIndex index of the slash request
     * @dev Only network middleware can call this function.
     */
    function requestSlash(
        address network,
        address operator,
        uint256 amount,
        uint48 captureTimestamp,
        bytes calldata hints
    ) external returns (uint256 slashIndex);

    /**
     * @notice Execute a slash with a given slash index using hints.
     * @param slashIndex index of the slash request
     * @param hints hints for checkpoints' indexes
     * @return slashedAmount amount of the collateral slashed
     * @dev Anyone can call this function.
     */
    function executeSlash(uint256 slashIndex, bytes calldata hints) external returns (uint256 slashedAmount);

    /**
     * @notice Veto a slash with a given slash index using hints.
     * @param slashIndex index of the slash request
     * @param hints hints for checkpoints' indexes
     * @dev Only a resolver can call this function.
     */
    function vetoSlash(uint256 slashIndex, bytes calldata hints) external;

    /**
     * @notice Set a resolver's shares for a network using hints.
     * @param resolver address of the resolver
     * @param shares amount of the shares to set (up to SHARES_BASE inclusively)
     * @param hints hints for checkpoints' indexes
     * @dev Only a network can call this function.
     */
    function setResolverShares(address resolver, uint256 shares, bytes calldata hints) external;
}
