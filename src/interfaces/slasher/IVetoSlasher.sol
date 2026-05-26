// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IBaseSlasher} from "./IBaseSlasher.sol";

uint64 constant VETO_SLASHER_TYPE = 1;

/**
 * @title IVetoSlasher
 * @notice Interface for the VetoSlasher contract.
 */
interface IVetoSlasher is IBaseSlasher {
    error AlreadySet();
    error InsufficientSlash();
    error InvalidCaptureTimestamp();
    error InvalidResolverSetEpochsDelay();
    error InvalidVetoDuration();
    error NoResolver();
    error NotNetwork();
    error NotResolver();
    error SlashPeriodEnded();
    error SlashRequestCompleted();
    error SlashRequestNotExist();
    error VetoPeriodEnded();
    error VetoPeriodNotEnded();

    /**
     * @notice Initial parameters needed for a slasher deployment.
     * @param baseParams Base parameters for slashers' deployment.
     * @param vetoDuration Duration of the veto period for a slash request.
     * @param resolverSetEpochsDelay Delay in epochs for a network to update a resolver.
     */
    struct InitParams {
        IBaseSlasher.BaseParams baseParams;
        uint48 vetoDuration;
        uint256 resolverSetEpochsDelay;
    }

    /**
     * @notice Structure for a slash request.
     * @param subnetwork Subnetwork that requested the slash.
     * @param operator Operator that could be slashed (if the request is not vetoed).
     * @param amount Maximum amount of the collateral to be slashed.
     * @param captureTimestamp Time point when the stake was captured.
     * @param vetoDeadline Deadline for the resolver to veto the slash (exclusively).
     * @param completed If the slash was vetoed/executed.
     */
    struct SlashRequest {
        bytes32 subnetwork;
        address operator;
        uint256 amount;
        uint48 captureTimestamp;
        uint48 vetoDeadline;
        bool completed;
    }

    /**
     * @notice Hints for a slash request.
     * @param slashableStakeHints Hints for the slashable stake checkpoints.
     */
    struct RequestSlashHints {
        bytes slashableStakeHints;
    }

    /**
     * @notice Hints for a slash execute.
     * @param captureResolverHint Hint for the resolver checkpoint at the capture time.
     * @param currentResolverHint Hint for the resolver checkpoint at the current time.
     * @param slashableStakeHints Hints for the slashable stake checkpoints.
     */
    struct ExecuteSlashHints {
        bytes captureResolverHint;
        bytes currentResolverHint;
        bytes slashableStakeHints;
    }

    /**
     * @notice Hints for a slash veto.
     * @param captureResolverHint Hint for the resolver checkpoint at the capture time.
     * @param currentResolverHint Hint for the resolver checkpoint at the current time.
     */
    struct VetoSlashHints {
        bytes captureResolverHint;
        bytes currentResolverHint;
    }

    /**
     * @notice Hints for a resolver set.
     * @param resolverHint Hint for the resolver checkpoint.
     */
    struct SetResolverHints {
        bytes resolverHint;
    }

    /**
     * @notice Extra data for the delegator.
     * @param slashableStake Amount of the slashable stake before the slash (cache).
     * @param stakeAt Amount of the stake at the capture time (cache).
     * @param slashIndex Index of the slash request.
     */
    struct DelegatorData {
        uint256 slashableStake;
        uint256 stakeAt;
        uint256 slashIndex;
    }

    /**
     * @notice Emitted when a slash request is created.
     * @param slashIndex Index of the slash request.
     * @param subnetwork Subnetwork that requested the slash.
     * @param operator Operator that could be slashed (if the request is not vetoed).
     * @param slashAmount Maximum amount of the collateral to be slashed.
     * @param captureTimestamp Time point when the stake was captured.
     * @param vetoDeadline Deadline for the resolver to veto the slash (exclusively).
     */
    event RequestSlash(
        uint256 indexed slashIndex,
        bytes32 indexed subnetwork,
        address indexed operator,
        uint256 slashAmount,
        uint48 captureTimestamp,
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
     * @notice Get the network registry's address.
     * @return Address Of the network registry.
     */
    function NETWORK_REGISTRY() external view returns (address);

    /**
     * @notice Get a particular slash request.
     * @param slashIndex Index of the slash request.
     * @return subnetwork Subnetwork that requested the slash.
     * @return operator Operator that could be slashed (if the request is not vetoed).
     * @return amount Maximum amount of the collateral to be slashed.
     * @return captureTimestamp Time point when the stake was captured.
     * @return vetoDeadline Deadline for the resolver to veto the slash (exclusively).
     * @return completed If the slash was vetoed/executed.
     */
    function slashRequests(uint256 slashIndex)
        external
        view
        returns (
            bytes32 subnetwork,
            address operator,
            uint256 amount,
            uint48 captureTimestamp,
            uint48 vetoDeadline,
            bool completed
        );

    /**
     * @notice Get a duration during which resolvers can veto slash requests.
     * @return Duration Of the veto period.
     */
    function vetoDuration() external view returns (uint48);

    /**
     * @notice Get a delay for networks in epochs to update a resolver.
     * @return Updating Resolver delay in epochs.
     */
    function resolverSetEpochsDelay() external view returns (uint256);

    /**
     * @notice Get a total number of slash requests.
     * @return Total Number of slash requests.
     */
    function slashRequestsLength() external view returns (uint256);

    /**
     * @notice Get a resolver for a given subnetwork at a particular timestamp using a hint.
     * @param subnetwork Full identifier of the subnetwork (address of the network concatenated with the uint96 identifier).
     * @param timestamp Timestamp to get the resolver at.
     * @param hint Hint for the checkpoint index.
     * @return Address Of the resolver.
     */
    function resolverAt(bytes32 subnetwork, uint48 timestamp, bytes memory hint) external view returns (address);

    /**
     * @notice Get a resolver for a given subnetwork using a hint.
     * @param subnetwork Full identifier of the subnetwork (address of the network concatenated with the uint96 identifier).
     * @param hint Hint for the checkpoint index.
     * @return Address Of the resolver.
     */
    function resolver(bytes32 subnetwork, bytes memory hint) external view returns (address);

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
     * @notice Veto a slash with a given slash index using hints.
     * @param slashIndex Index of the slash request.
     * @param hints Hints for checkpoints' indexes.
     * @dev Only a resolver can call this function.
     */
    function vetoSlash(uint256 slashIndex, bytes calldata hints) external;

    /**
     * @notice Set a resolver for a subnetwork using hints.
     * @param identifier Identifier of the subnetwork.
     * @param resolver Address of the resolver.
     * @param hints Hints for checkpoints' indexes.
     * @dev Only a network can call this function.
     */
    function setResolver(uint96 identifier, address resolver, bytes calldata hints) external;
}
