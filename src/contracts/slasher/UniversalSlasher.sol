// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {BaseSlasher} from "./BaseSlasher.sol";

import {Checkpoints} from "../libraries/Checkpoints.sol";
import {Subnetwork} from "../libraries/Subnetwork.sol";
import {UniversalDelegatorIndex} from "../libraries/UniversalDelegatorIndex.sol";

import {IRegistry} from "../../interfaces/common/IRegistry.sol";
import {IVault} from "../../interfaces/vault/IVault.sol";
import {IUniversalSlasher} from "../../interfaces/slasher/IUniversalSlasher.sol";
import {IMigratableEntity} from "../../interfaces/common/IMigratableEntity.sol";
import {IUniversalDelegator} from "../../interfaces/delegator/IUniversalDelegator.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

contract UniversalSlasher is BaseSlasher, IUniversalSlasher {
    using Math for uint256;
    using SafeCast for uint256;
    using Checkpoints for Checkpoints.Trace208;
    using Checkpoints for Checkpoints.Trace256;
    using Subnetwork for address;
    using UniversalDelegatorIndex for uint96;

    /**
     * @inheritdoc IUniversalSlasher
     */
    address public immutable NETWORK_REGISTRY;

    /**
     * @inheritdoc IUniversalSlasher
     */
    SlashRequest[] public slashRequests;

    /**
     * @inheritdoc IUniversalSlasher
     */
    uint48 public vetoDuration;

    /**
     * @inheritdoc IUniversalSlasher
     */
    uint256 public resolverSetEpochsDelay;

    mapping(bytes32 subnetwork => Checkpoints.Trace208 value) internal _resolver;

    mapping(uint96 groupIndex => Checkpoints.Trace256 amount) internal _groupCumulativeSlash;

    constructor(
        address vaultFactory,
        address networkMiddlewareService,
        address networkRegistry,
        address slasherFactory,
        uint64 entityType
    ) BaseSlasher(vaultFactory, networkMiddlewareService, slasherFactory, entityType) {
        NETWORK_REGISTRY = networkRegistry;
    }

    /**
     * @inheritdoc IUniversalSlasher
     */
    function slashRequestsLength() external view returns (uint256) {
        return slashRequests.length;
    }

    /**
     * @inheritdoc IUniversalSlasher
     */
    function resolverAt(bytes32 subnetwork, uint48 timestamp, bytes memory hint) public view returns (address) {
        return address(uint160(_resolver[subnetwork].upperLookupRecent(timestamp, hint)));
    }

    /**
     * @inheritdoc IUniversalSlasher
     */
    function resolver(bytes32 subnetwork, bytes memory hint) public view returns (address) {
        return resolverAt(subnetwork, Time.timestamp(), hint);
    }

    /**
     * @inheritdoc IUniversalSlasher
     */
    function groupCumulativeSlashAt(uint96 groupIndex, uint48 timestamp, bytes memory hint)
        public
        view
        returns (uint256)
    {
        return _groupCumulativeSlash[groupIndex].upperLookupRecent(timestamp, hint);
    }

    /**
     * @inheritdoc IUniversalSlasher
     */
    function groupCumulativeSlash(uint96 groupIndex) public view returns (uint256) {
        return _groupCumulativeSlash[groupIndex].latest();
    }

    /**
     * @inheritdoc IUniversalSlasher
     */
    function requestSlash(
        bytes32 subnetwork,
        address operator,
        uint256 amount,
        uint48 captureTimestamp,
        bytes calldata hints
    ) external nonReentrant onlyNetworkMiddleware(subnetwork) returns (uint256 slashIndex) {
        RequestSlashHints memory requestSlashHints;
        if (hints.length > 0) {
            requestSlashHints = abi.decode(hints, (RequestSlashHints));
        }

        // TODO: saturatingSub
        if (
            captureTimestamp < Time.timestamp() + vetoDuration - IVault(vault).epochDuration()
                || captureTimestamp >= Time.timestamp()
        ) {
            revert InvalidCaptureTimestamp();
        }

        amount = Math.min(
            amount, slashableStake(subnetwork, operator, captureTimestamp, requestSlashHints.slashableStakeHints)
        );
        if (amount == 0) {
            revert InsufficientSlash();
        }

        uint48 vetoDeadline = Time.timestamp() + vetoDuration;

        slashIndex = slashRequests.length;
        slashRequests.push(
            SlashRequest({
                subnetwork: subnetwork,
                operator: operator,
                amount: amount,
                captureTimestamp: captureTimestamp,
                vetoDeadline: vetoDeadline,
                completed: false
            })
        );

        emit RequestSlash(slashIndex, subnetwork, operator, amount, captureTimestamp, vetoDeadline);
    }

    /**
     * @inheritdoc IUniversalSlasher
     */
    function executeSlash(uint256 slashIndex, bytes calldata hints)
        external
        nonReentrant
        returns (uint256 slashedAmount)
    {
        ExecuteSlashHints memory executeSlashHints;
        if (hints.length > 0) {
            executeSlashHints = abi.decode(hints, (ExecuteSlashHints));
        }

        if (slashIndex >= slashRequests.length) {
            revert SlashRequestNotExist();
        }

        SlashRequest storage request = slashRequests[slashIndex];

        _checkNetworkMiddleware(request.subnetwork);

        if (
            resolverAt(request.subnetwork, request.captureTimestamp, executeSlashHints.captureResolverHint)
                    != address(0)
                && resolverAt(request.subnetwork, Time.timestamp() - 1, executeSlashHints.currentResolverHint)
                    != address(0) && request.vetoDeadline > Time.timestamp()
        ) {
            revert VetoPeriodNotEnded();
        }

        if (Time.timestamp() - request.captureTimestamp > IVault(vault).epochDuration()) {
            revert SlashPeriodEnded();
        }

        (uint256 slashableStake_, uint256 stakeAt) = _slashableStake(
            request.subnetwork, request.operator, request.captureTimestamp, executeSlashHints.slashableStakeHints
        );
        slashedAmount = Math.min(request.amount, slashableStake_);
        if (slashedAmount == 0) {
            revert InsufficientSlash();
        }

        if (request.completed) {
            revert SlashRequestCompleted();
        }

        request.completed = true;

        _updateLatestSlashedCaptureTimestamp(request.subnetwork, request.operator, request.captureTimestamp);

        _updateCumulativeSlash(request.subnetwork, request.operator, slashedAmount);
        _updateGroupCumulativeSlash(
            request.subnetwork, request.operator, slashedAmount, request.captureTimestamp, executeSlashHints.slotOfHint
        );

        _delegatorOnSlash(
            request.subnetwork,
            request.operator,
            slashedAmount,
            request.captureTimestamp,
            abi.encode(
                IUniversalSlasher.DelegatorData({
                    slashableStake: slashableStake_, stakeAt: stakeAt, slashIndex: slashIndex
                })
            )
        );

        _vaultOnSlash(slashedAmount, request.captureTimestamp);

        _burnerOnSlash(request.subnetwork, request.operator, slashedAmount, request.captureTimestamp);

        emit ExecuteSlash(slashIndex, slashedAmount);
    }

    /**
     * @inheritdoc IUniversalSlasher
     */
    function vetoSlash(uint256 slashIndex, bytes calldata hints) external nonReentrant {
        VetoSlashHints memory vetoSlashHints;
        if (hints.length > 0) {
            vetoSlashHints = abi.decode(hints, (VetoSlashHints));
        }

        if (slashIndex >= slashRequests.length) {
            revert SlashRequestNotExist();
        }

        SlashRequest storage request = slashRequests[slashIndex];

        address captureResolver =
            resolverAt(request.subnetwork, request.captureTimestamp, vetoSlashHints.captureResolverHint);
        if (
            captureResolver == address(0)
                || resolverAt(request.subnetwork, Time.timestamp() - 1, vetoSlashHints.currentResolverHint)
                    == address(0)
        ) {
            revert NoResolver();
        }

        if (msg.sender != captureResolver) {
            revert NotResolver();
        }

        if (request.vetoDeadline <= Time.timestamp()) {
            revert VetoPeriodEnded();
        }

        if (request.completed) {
            revert SlashRequestCompleted();
        }

        request.completed = true;

        emit VetoSlash(slashIndex, msg.sender);
    }

    function setResolver(uint96 identifier, address resolver_, bytes calldata hints) external nonReentrant {
        SetResolverHints memory setResolverHints;
        if (hints.length > 0) {
            setResolverHints = abi.decode(hints, (SetResolverHints));
        }

        if (!IRegistry(NETWORK_REGISTRY).isEntity(msg.sender)) {
            revert NotNetwork();
        }

        address vault_ = vault;
        bytes32 subnetwork = (msg.sender).subnetwork(identifier);
        (bool exists, uint48 latestTimestamp,) = _resolver[subnetwork].latestCheckpoint();
        if (exists) {
            if (latestTimestamp > Time.timestamp()) {
                _resolver[subnetwork].pop();
            } else if (resolver_ == address(uint160(_resolver[subnetwork].latest()))) {
                revert AlreadySet();
            }

            if (resolver_ != address(uint160(_resolver[subnetwork].latest()))) {
                _resolver[subnetwork].push(
                    (IVault(vault_).currentEpochStart() + resolverSetEpochsDelay * IVault(vault_).epochDuration())
                    .toUint48(),
                    uint160(resolver_)
                );
            }
        } else {
            if (resolver_ == address(0)) {
                revert AlreadySet();
            }

            _resolver[subnetwork].push(Time.timestamp(), uint160(resolver_));
        }

        emit SetResolver(subnetwork, resolver_);
    }

    function _slashableStake(bytes32 subnetwork, address operator, uint48 captureTimestamp, bytes memory hints)
        internal
        view
        override
        returns (uint256 slashableStake_, uint256 stakeAmount)
    {
        OuterSlashableStakeHints memory outerSlashableStakeHints;
        if (hints.length > 0) {
            outerSlashableStakeHints = abi.decode(hints, (OuterSlashableStakeHints));
        }
        address delegator = IVault(vault).delegator();
        uint96 groupIndex = IUniversalDelegator(delegator)
            .getSlotOfAt(subnetwork, operator, captureTimestamp, outerSlashableStakeHints.slotOfHints).getParentIndex()
            .getParentIndex();
        uint256 groupAllocatedAmount = IUniversalDelegator(delegator)
            .getAllocatedAt(groupIndex, captureTimestamp, outerSlashableStakeHints.groupAllocatedHints);
        (slashableStake_, stakeAmount) =
            super._slashableStake(subnetwork, operator, captureTimestamp, outerSlashableStakeHints.slashableStakeHints);
        return (
            Math.min(
                slashableStake_,
                groupAllocatedAmount
                    - Math.min(
                        groupCumulativeSlash(groupIndex)
                            - groupCumulativeSlashAt(
                                groupIndex, captureTimestamp, outerSlashableStakeHints.groupCumulativeSlashFromHint
                            ),
                        groupAllocatedAmount
                    )
            ),
            stakeAmount
        );
    }

    function _updateGroupCumulativeSlash(
        bytes32 subnetwork,
        address operator,
        uint256 amount,
        uint48 captureTimestamp,
        bytes memory hint
    ) internal {
        uint96 groupIndex = IUniversalDelegator(IVault(vault).delegator())
            .getSlotOfAt(subnetwork, operator, captureTimestamp, hint).getParentIndex().getParentIndex();
        _groupCumulativeSlash[groupIndex].push(Time.timestamp(), groupCumulativeSlash(groupIndex) + amount);
    }

    function __initialize(address vault_, bytes memory data) internal override returns (BaseParams memory) {
        if (IMigratableEntity(vault_).version() == 1) {
            revert OldVault();
        }

        (InitParams memory params) = abi.decode(data, (InitParams));

        uint48 epochDuration = IVault(vault_).epochDuration();
        if (params.vetoDuration >= epochDuration) {
            revert InvalidVetoDuration();
        }

        if (params.resolverSetEpochsDelay < 3) {
            revert InvalidResolverSetEpochsDelay();
        }

        vetoDuration = params.vetoDuration;

        resolverSetEpochsDelay = params.resolverSetEpochsDelay;

        return params.baseParams;
    }
}
