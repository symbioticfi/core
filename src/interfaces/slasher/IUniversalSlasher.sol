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
    /* ERRORS */

    /**
     * @notice Raised when there is not enough gas left for the burner hook call.
     */
    error InsufficientBurnerGas();

    /**
     * @notice Raised when the requested slash amount is zero after validation.
     */
    error InsufficientSlash();

    /**
     * @notice Raised when the resolver set delay is outside allowed bounds.
     */
    error InvalidResolverSetEpochsDelay();

    /**
     * @notice Raised when the veto duration is outside allowed bounds.
     */
    error InvalidVetoDuration();

    /**
     * @notice Raised when burner-hook mode is enabled but the vault has no burner.
     */
    error NoBurner();

    /**
     * @notice Raised when migration functions are called outside migration mode.
     */
    error NotMigrating();

    /**
     * @notice Raised when the caller is not a registered network.
     */
    error NotNetwork();

    /**
     * @notice Raised when the caller is not the network middleware for the subnetwork.
     */
    error NotNetworkMiddleware();

    /**
     * @notice Raised when the caller is not the configured resolver.
     */
    error NotResolver();

    /**
     * @notice Raised when the provided vault is invalid.
     */
    error NotVault();

    /**
     * @notice Raised when the connected vault version is older than required.
     */
    error OldVault();

    /**
     * @notice Raised when the slash request has already been completed.
     */
    error SlashRequestCompleted();

    /**
     * @notice Raised when the veto period has already ended.
     */
    error VetoPeriodEnded();

    /**
     * @notice Raised when the veto period has not ended yet.
     */
    error VetoPeriodNotEnded();

    /* STRUCTS */

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
     * @notice Initial parameters needed for a slasher deployment.
     * @param isBurnerHook If burner hook calls are enabled on slashes.
     * @param vetoDuration Duration of the veto period for a slash request.
     * @param resolverSetDelay Delay in seconds for a network to update a resolver.
     */
    struct InitParams {
        bool isBurnerHook;
        uint48 vetoDuration;
        uint48 resolverSetDelay;
    }

    /**
     * @notice Base parameters needed for slashers' deployment.
     * @param isBurnerHook If the burner is needed to be called on a slashing.
     */
    struct BaseParams {
        bool isBurnerHook;
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

    /* EVENTS */

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

    /**
     * @notice Emitted when owed slashing is synced for an operator.
     * @param subnetwork Full identifier of the subnetwork.
     * @param operator Address of the operator.
     * @param slashed Amount of collateral synced and burned.
     */
    event SyncOwedSlash(bytes32 indexed subnetwork, address indexed operator, uint256 slashed);

    /**
     * @notice Emitted when a vault is initialized.
     * @param params Initial parameters for the slasher.
     */
    event Initialize(InitParams params);

    /* FUNCTIONS */

    /**
     * @notice Get the vault's address.
     * @return Address of the vault to perform slashings on.
     */
    function vault() external view returns (address);

    /**
     * @notice Timestamp when migration from the previous slasher occurred.
     * @return migrateTimestamp Migration timestamp.
     */
    function migrateTimestamp() external view returns (uint48 migrateTimestamp);

    /**
     * @notice Address of the previous slasher used for legacy reads after migration.
     * @return oldSlasher Previous slasher address.
     */
    function oldSlasher() external view returns (address oldSlasher);

    /**
     * @notice Get if the burner is needed to be called on a slashing.
     * @return If the burner is a hook.
     */
    function isBurnerHook() external view returns (bool);

    /**
     * @notice Get a duration during which resolvers can veto slash requests.
     * @return Duration of the veto period.
     */
    function vetoDuration() external view returns (uint48);

    /**
     * @notice Get a delay for networks in seconds to update a resolver.
     * @return Updating resolver delay in seconds.
     */
    function resolverSetDelay() external view returns (uint48);

    /**
     * @notice Get whether a resolver was ever set for a subnetwork on this slasher.
     * @param subnetwork Full identifier of the subnetwork.
     * @return Whether resolver state exists locally for the subnetwork.
     * @dev Used to distinguish fresh local state from legacy fallback reads after migration.
     */
    function isResolverSet(bytes32 subnetwork) external view returns (bool);

    /**
     * @notice Get pending resolver activation data for a subnetwork.
     * @param subnetwork Full identifier of the subnetwork.
     * @return data Encoded pending resolver address and activation timestamp.
     */
    function pendingResolverData(bytes32 subnetwork) external view returns (bytes32);

    /**
     * @notice Get a total amount of owed slashing.
     * @return Total amount of owed slashing.
     */
    function totalOwed() external view returns (uint256);

    /**
     * @notice Get owed slash amount for a subnetwork and operator.
     * @param subnetwork Full identifier of the subnetwork.
     * @param operator Address of the operator.
     * @return amount Outstanding slash amount not yet synced to burner.
     */
    function owed(bytes32 subnetwork, address operator) external view returns (uint256);

    /**
     * @notice Get a total number of slash requests.
     * @return Total number of slash requests.
     */
    function slashRequestsLength() external view returns (uint256);

    /**
     * @notice Get a particular slash request.
     * @param slashIndex Index of the slash request.
     * @return request Slash request.
     */
    function slashRequests(uint256 slashIndex) external view returns (SlashRequest memory request);

    /**
     * @notice Get a resolver for a given subnetwork.
     * @param subnetwork Full identifier of the subnetwork (address of the network concatenated with the uint96 identifier).
     * @return Address of the resolver.
     */
    function resolver(bytes32 subnetwork) external view returns (address);

    /**
     * @notice Get a slashable amount of stake at a given capture timestamp.
     * @param subnetwork Full identifier of the subnetwork (address of the network concatenated with the uint96 identifier).
     * @param operator Address of the operator.
     * @param captureTimestamp Time point to get the stake amount at.
     * @return Slashable amount of the stake.
     * @dev Can use 0 as a capture timestamp to get the current stake amount.
     */
    function slashableStake(bytes32 subnetwork, address operator, uint48 captureTimestamp, bytes calldata)
        external
        view
        returns (uint256);

    /**
     * @notice Perform a slash using a subnetwork for a particular operator by a given amount.
     * @param subnetwork Full identifier of the subnetwork (address of the network concatenated with the uint96 identifier).
     * @param operator Address of the operator.
     * @param amount Maximum amount of the collateral to be slashed.
     * @return slashedAmount Virtual amount of the collateral slashed.
     */
    function slash(bytes32 subnetwork, address operator, uint256 amount) external returns (uint256 slashedAmount);

    /**
     * @notice Request a slash using a subnetwork for a particular operator by a given amount.
     * @param subnetwork Full identifier of the subnetwork (address of the network concatenated with the uint96 identifier).
     * @param operator Address of the operator.
     * @param amount Maximum amount of the collateral to be slashed.
     * @param captureTimestamp Legacy parameter reserved for compatibility (can just use 0 instead).
     * @return slashIndex Index of the slash request.
     * @dev Only a network middleware can call this function.
     */
    function requestSlash(bytes32 subnetwork, address operator, uint256 amount, uint48 captureTimestamp, bytes calldata)
        external
        returns (uint256 slashIndex);

    /**
     * @notice Execute a slash with a given slash index.
     * @param slashIndex Index of the slash request.
     * @return slashedAmount Virtual amount of collateral slashed.
     * @dev Only a network middleware can call this function.
     */
    function executeSlash(uint256 slashIndex, bytes calldata) external returns (uint256 slashedAmount);

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
