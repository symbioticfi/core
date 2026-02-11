// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

uint64 constant UNIVERSAL_SLASHER_TYPE = 2;

uint256 constant BURNER_GAS_LIMIT = 150_000;
uint256 constant BURNER_RESERVE = 20_000;

/**
 * @title IUniversalSlasher
 * @notice Interface for the UniversalSlasher contract.
 */
interface IUniversalSlasher {
    error AlreadySet();
    error InsufficientSlash();
    error InvalidCaptureTimestamp();
    error InvalidResolverSetEpochsDelay();
    error InvalidVetoDuration();
    error NoResolver();
    error NotNetwork();
    error NotResolver();
    error SlashRequestCompleted();
    error SlashRequestNotExist();
    error VetoPeriodEnded();
    error VetoPeriodNotEnded();
    error OldVault();
    error NotMigrating();
    error WrongMigrate();
    error NoBurner();
    error InsufficientBurnerGas();
    error NotNetworkMiddleware();
    error NotVault();

    /**
     * @notice Base parameters needed for slashers' deployment.
     * @param isBurnerHook If the burner is needed to be called on a slashing.
     */
    struct BaseParams {
        bool isBurnerHook;
    }

    /**
     * @notice Hints for a slashable stake.
     * @param stakeHints Hints for the stake checkpoints.
     * @param cumulativeSlashFromHint Hint for the cumulative slash amount at a capture timestamp.
     * @param slotOfHints Hints for the slot lookup.
     * @param groupAllocatedHints Hints for the group allocation lookup.
     * @param groupCumulativeSlashFromHint Hint for the group cumulative slash amount at a capture timestamp.
     */
    struct SlashableStakeHints {
        bytes stakeHints;
        bytes cumulativeSlashFromHint;
        bytes slotOfHints;
        bytes groupAllocatedHints;
        bytes groupCumulativeSlashFromHint;
    }

    /**
     * @notice General data for the delegator.
     * @param slasherType Type of the slasher.
     * @param data Slasher-dependent data for the delegator.
     */
    struct GeneralDelegatorData {
        uint64 slasherType;
        bytes data;
    }

    /**
     * @notice Initial parameters needed for a slasher deployment.
     * @param baseParams Base parameters for slashers' deployment.
     * @param vetoDuration Duration of the veto period for a slash request.
     * @param resolverSetDelay Delay in seconds for a network to update a resolver.
     */
    struct InitParams {
        bool isBurnerHook;
        uint48 vetoDuration;
        uint48 resolverSetDelay;
    }

    /**
     * @notice Structure for a slash request.
     * @param subnetwork Subnetwork that requested the slash.
     * @param operator Operator that could be slashed (if the request is not vetoed).
     * @param amount Maximum amount of the collateral to be slashed.
     * @param createdAt Time point when the request was created (capture timestamp if legacy).
     * @param vetoDeadline Deadline for the resolver to veto the slash (exclusively).
     * @param completed If the slash was vetoed/executed.
     */
    struct SlashRequest {
        bytes32 subnetwork;
        address operator;
        uint48 createdAt;
        uint256 amount;
        address resolver;
        uint48 vetoDeadline;
        bool completed;
    }

    /**
     * @notice Emitted when a slash request is created.
     * @param slashIndex Index of the slash request.
     * @param subnetwork Subnetwork that requested the slash.
     * @param operator Operator that could be slashed (if the request is not vetoed).
     * @param slashAmount Maximum amount of the collateral to be slashed.
     * @param vetoDeadline Deadline for the resolver to veto the slash (exclusively).
     */
    event RequestSlash(
        uint256 indexed slashIndex,
        bytes32 indexed subnetwork,
        address indexed operator,
        uint256 slashAmount,
        uint48 vetoDeadline
    );

    /**
     * @notice Emitted when a slash request is executed.
     * @param slashIndex Index of the slash request.
     * @param slashedAmount Virtual amount of the collateral slashed.
     */
    event ExecuteSlash(uint256 indexed slashIndex, uint256 slashedAmount);

    /**
     * @notice Emitted when a slash request is vetoed.
     * @param slashIndex Index of the slash request.
     * @param resolver Address of the resolver that vetoed the slash.
     */
    event VetoSlash(uint256 indexed slashIndex, address indexed resolver);

    /**
     * @notice Emitted when a resolver is set.
     * @param subnetwork Full identifier of the subnetwork (address of the network concatenated with the uint96 identifier).
     * @param resolver Address of the resolver.
     */
    event SetResolver(bytes32 indexed subnetwork, address resolver);

    event SyncOwedSlash(bytes32 indexed subnetwork, address indexed operator, uint256 slashed);

    /**
     * @notice Emitted when a vault is initialized.
     * @param params Initial parameters for the slasher.
     */
    event Initialize(InitParams params);

    /**
     * @notice Get the vault's address.
     * @return Address Of the vault to perform slashings on.
     */
    function vault() external view returns (address);

    /**
     * @notice Get if the burner is needed to be called on a slashing.
     * @return If The burner is a hook.
     */
    function isBurnerHook() external view returns (bool);

    /**
     * @notice Get a slashable amount of a stake got at a given capture timestamp using hints.
     * @param subnetwork Full identifier of the subnetwork (address of the network concatenated with the uint96 identifier).
     * @param operator Address of the operator.
     * @param captureTimestamp Time point to get the stake amount at.
     * @param hints Hints for the checkpoints' indexes.
     * @return Slashable Amount of the stake.
     */
    function slashableStake(bytes32 subnetwork, address operator, uint48 captureTimestamp, bytes memory hints)
        external
        view
        returns (uint256);

    /**
     * @notice Get the network registry's address.
     * @return Address Of the network registry.
     */
    /**
     * @notice Get a duration during which resolvers can veto slash requests.
     * @return Duration Of the veto period.
     */
    function vetoDuration() external view returns (uint48);

    /**
     * @notice Get a total number of slash requests.
     * @return Total Number of slash requests.
     */
    function slashRequestsLength() external view returns (uint256);

    /**
     * @notice Get a particular slash request.
     * @param slashIndex Index of the slash request.
     * @return request Slash request.
     */
    function slashRequests(uint256 slashIndex) external view returns (SlashRequest memory request);

    /**
     * @notice Get a delay for networks in seconds to update a resolver.
     * @return Updating Resolver delay in seconds.
     */
    function resolverSetDelay() external view returns (uint48);

    /**
     * @notice Get a resolver for a given subnetwork.
     * @param subnetwork Full identifier of the subnetwork (address of the network concatenated with the uint96 identifier).
     * @return Address Of the resolver.
     */
    function resolver(bytes32 subnetwork) external view returns (address);

    function pendingResolverData(bytes32 subnetwork) external view returns (bytes32);

    /**
     * @notice Request a slash using a subnetwork for a particular operator by a given amount using hints.
     * @param subnetwork Full identifier of the subnetwork (address of the network concatenated with the uint96 identifier).
     * @param operator Address of the operator.
     * @param amount Maximum amount of the collateral to be slashed.
     * @param captureTimestamp Time point when the stake was captured.
     * @param hints Hints for checkpoints' indexes.
     * @return slashIndex Index of the slash request.
     * @dev Only a network middleware can call this function.
     */
    function requestSlash(
        bytes32 subnetwork,
        address operator,
        uint256 amount,
        uint48 captureTimestamp,
        bytes calldata hints
    ) external returns (uint256 slashIndex);

    /**
     * @notice Execute a slash with a given slash index using hints.
     * @param slashIndex Index of the slash request.
     * @param hints Hints for checkpoints' indexes.
     * @return slashedAmount Virtual amount of the collateral slashed.
     * @dev Only a network middleware can call this function.
     */
    function executeSlash(uint256 slashIndex, bytes calldata hints) external returns (uint256 slashedAmount);

    /**
     * @notice Veto a slash with a given slash index.
     * @param slashIndex Index of the slash request.
     * @dev Only a resolver can call this function.
     */
    function vetoSlash(uint256 slashIndex) external;

    /**
     * @notice Set a resolver for a subnetwork.
     * @param identifier Identifier of the subnetwork.
     * @param resolver Address of the resolver.
     * @dev Only a network can call this function.
     */
    function setResolver(uint96 identifier, address resolver) external;

    /**
     * @notice Sync owed slashing.
     * @param subnetwork Full identifier of the subnetwork (address of the network concatenated with the uint96 identifier).
     * @param operator Address of the operator.
     * @return slashed Amount of the collateral slashed.
     */
    function syncOwedSlash(bytes32 subnetwork, address operator) external returns (uint256 slashed);
}
