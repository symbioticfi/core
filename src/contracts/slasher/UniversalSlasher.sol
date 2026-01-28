// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {BaseSlasher} from "./BaseSlasher.sol";
import {VaultV2} from "../vault/VaultV2.sol";

import {Checkpoints} from "../libraries/Checkpoints.sol";
import {Subnetwork} from "../libraries/Subnetwork.sol";
import {UniversalDelegatorIndex} from "../libraries/UniversalDelegatorIndex.sol";

import {IBaseSlasher} from "../../interfaces/slasher/IBaseSlasher.sol";
import {IEntity} from "../../interfaces/common/IEntity.sol";
import {IMigratableEntity} from "../../interfaces/common/IMigratableEntity.sol";
import {IRegistry} from "../../interfaces/common/IRegistry.sol";
import {IUniversalDelegator} from "../../interfaces/delegator/IUniversalDelegator.sol";
import {IUniversalSlasher} from "../../interfaces/slasher/IUniversalSlasher.sol";
import {IVaultV2} from "../../interfaces/vault/IVaultV2.sol";
import {IVetoSlasher} from "../../interfaces/slasher/IVetoSlasher.sol";

import {FixedPointMathLib as Math} from "@solady/src/utils/FixedPointMathLib.sol";
import {SafeCastLib as SafeCast} from "@solady/src/utils/SafeCastLib.sol";

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
    uint48 public vetoDuration;

    /**
     * @inheritdoc IUniversalSlasher
     */
    uint48 public resolverSetDelay;

    mapping(bytes32 subnetwork => mapping(address operator => mapping(uint48 captureTimestamp => uint256 amount)))
        public owed;

    SlashRequest[] internal _slashRequests;

    mapping(bytes32 subnetwork => address value) internal _resolver;

    mapping(bytes32 subnetwork => uint256 value) public pendingResolverData;

    mapping(uint96 groupIndex => Checkpoints.Trace256 amount) internal _groupCumulativeSlash;

    uint48 internal _migrateTimestamp;

    address internal _oldDelegator;

    address internal _oldSlasher;

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
    function slashRequestsLength() public view returns (uint256) {
        return _slashRequests.length;
    }

    /**
     * @inheritdoc IUniversalSlasher
     */
    function slashRequests(uint256 slashIndex) public view returns (SlashRequest memory request) {
        request = _slashRequests[slashIndex];

        if (request.amount == 0) {
            (request.subnetwork, request.operator, request.amount, request.captureTimestamp, request.vetoDeadline,) =
                IVetoSlasher(_oldSlasher).slashRequests(slashIndex);

            request.resolver =
                IVetoSlasher(_oldSlasher).resolverAt(request.subnetwork, request.captureTimestamp, new bytes(0));
            if (request.resolver != address(0)) {
                // TODO: remove it, or add comment regarding block.timestamp versus slashIndex
                request.resolver =
                    IVetoSlasher(_oldSlasher).resolverAt(request.subnetwork, uint48(block.timestamp) - 1, new bytes(0));
            }
        }
    }

    /**
     * @inheritdoc IUniversalSlasher
     */
    function resolver(bytes32 subnetwork) public view returns (address) {
        return uint48(pendingResolverData[subnetwork]) == 0 || block.timestamp < uint48(pendingResolverData[subnetwork])
            ? _resolver[subnetwork]
            : address(uint160(pendingResolverData[subnetwork] >> 48));
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
    ) public nonReentrant onlyNetworkMiddleware(subnetwork) returns (uint256 slashIndex) {
        RequestSlashHints memory requestSlashHints;
        if (hints.length > 0) {
            requestSlashHints = abi.decode(hints, (RequestSlashHints));
        }

        address resolver = resolver(subnetwork);
        uint48 vetoDeadline = uint48(block.timestamp) + (resolver > address(0) ? vetoDuration : 0);
        if (
            captureTimestamp > 0
                && (captureTimestamp < uint256(vetoDeadline).saturatingSub(IVaultV2(vault).epochDuration())
                    || captureTimestamp >= uint48(block.timestamp))
        ) {
            revert InvalidCaptureTimestamp();
        }

        captureTimestamp = captureTimestamp == 0 ? uint48(block.timestamp) : captureTimestamp;
        amount = Math.min(
            amount, slashableStake(subnetwork, operator, captureTimestamp, requestSlashHints.slashableStakeHints)
        );
        if (amount == 0) {
            revert InsufficientSlash();
        }

        slashIndex = _slashRequests.length;
        _slashRequests.push(
            SlashRequest({
                subnetwork: subnetwork,
                operator: operator,
                amount: amount,
                captureTimestamp: captureTimestamp,
                resolver: resolver,
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
        public
        nonReentrant
        returns (uint256 slashedAmount)
    {
        ExecuteSlashHints memory executeSlashHints;
        if (hints.length > 0) {
            executeSlashHints = abi.decode(hints, (ExecuteSlashHints));
        }

        if (slashIndex >= _slashRequests.length) {
            revert SlashRequestNotExist();
        }

        SlashRequest memory request = slashRequests(slashIndex);

        _checkNetworkMiddleware(request.subnetwork);

        if (request.vetoDeadline > uint48(block.timestamp)) {
            revert VetoPeriodNotEnded();
        }

        if (uint48(block.timestamp) - request.captureTimestamp > IVaultV2(vault).epochDuration()) {
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

        _slashRequests[slashIndex].completed = true;

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

        (, uint256 owed_) = VaultV2(vault).onSlash(slashedAmount, request.captureTimestamp);
        if (owed_ > 0) {
            owed[request.subnetwork][request.operator][request.captureTimestamp] += owed_;
        }

        _burnerOnSlash(request.subnetwork, request.operator, slashedAmount, request.captureTimestamp);

        emit ExecuteSlash(slashIndex, slashedAmount);
    }

    /**
     * @inheritdoc IUniversalSlasher
     */
    function vetoSlash(uint256 slashIndex, bytes calldata hints) public nonReentrant {
        VetoSlashHints memory vetoSlashHints;
        if (hints.length > 0) {
            vetoSlashHints = abi.decode(hints, (VetoSlashHints));
        }

        if (slashIndex >= _slashRequests.length) {
            revert SlashRequestNotExist();
        }

        SlashRequest memory request = slashRequests(slashIndex);

        if (request.resolver != msg.sender) {
            revert NotResolver();
        }

        if (request.vetoDeadline <= uint48(block.timestamp)) {
            revert VetoPeriodEnded();
        }

        if (request.completed) {
            revert SlashRequestCompleted();
        }

        _slashRequests[slashIndex].completed = true;

        emit VetoSlash(slashIndex, msg.sender);
    }

    /**
     * @inheritdoc IUniversalSlasher
     */
    function setResolver(uint96 identifier, address newResolver, bytes calldata hints) public nonReentrant {
        SetResolverHints memory setResolverHints;
        if (hints.length > 0) {
            setResolverHints = abi.decode(hints, (SetResolverHints));
        }

        if (!IRegistry(NETWORK_REGISTRY).isEntity(msg.sender)) {
            revert NotNetwork();
        }

        bytes32 subnetwork = (msg.sender).subnetwork(identifier);
        if (_resolver[subnetwork] != resolver(subnetwork)) {
            _resolver[subnetwork] = resolver(subnetwork);
            pendingResolverData[subnetwork] = 0;
        }

        if (_resolver[subnetwork] == address(0)) {
            _resolver[subnetwork] = newResolver;
        } else {
            pendingResolverData[subnetwork] = uint256(uint160(newResolver)) << 48 | (block.timestamp + resolverSetDelay);
        }

        emit SetResolver(subnetwork, newResolver);
    }

    function syncOwedSlash(bytes32 subnetwork, address operator, uint48 captureTimestamp) public {
        uint256 oldOwed = owed[subnetwork][operator][captureTimestamp];
        uint256 newOwed = VaultV2(vault).syncOwedSlash(oldOwed);
        owed[subnetwork][operator][captureTimestamp] = newOwed;
        _burnerOnSlash(subnetwork, operator, oldOwed - newOwed, captureTimestamp);
    }

    function _updateGroupCumulativeSlash(
        bytes32 subnetwork,
        address operator,
        uint256 amount,
        uint48 captureTimestamp,
        bytes memory hint
    ) internal {
        uint96 groupIndex = IUniversalDelegator(IVaultV2(vault).delegator())
            .getSlotOfAt(subnetwork, operator, captureTimestamp, hint).getParentIndex().getParentIndex();
        _groupCumulativeSlash[groupIndex].push(uint48(block.timestamp), groupCumulativeSlash(groupIndex) + amount);
    }

    function __initialize(address vault_, bytes memory data) internal override returns (BaseParams memory) {
        if (IMigratableEntity(vault_).version() < 3) {
            revert OldVault();
        }

        (InitParams memory params) = abi.decode(data, (InitParams));

        if (params.vetoDuration >= IVaultV2(vault_).epochDuration()) {
            revert InvalidVetoDuration();
        }

        if (params.resolverSetDelay <= IVaultV2(vault_).epochDuration()) {
            revert InvalidResolverSetEpochsDelay();
        }

        vetoDuration = params.vetoDuration;

        resolverSetDelay = params.resolverSetDelay;

        return params.baseParams;
    }

    function cumulativeSlashAt(bytes32 subnetwork, address operator, uint48 timestamp, bytes memory hint)
        public
        view
        override(BaseSlasher, IBaseSlasher)
        returns (uint256)
    {
        if (timestamp >= _migrateTimestamp) {
            return super.cumulativeSlashAt(subnetwork, operator, timestamp, hint);
        }
        return IBaseSlasher(_oldSlasher).cumulativeSlashAt(subnetwork, operator, timestamp, hint);
    }

    function cumulativeSlash(bytes32 subnetwork, address operator)
        public
        view
        override(BaseSlasher, IBaseSlasher)
        returns (uint256)
    {
        if (_oldSlasher == address(0) || _cumulativeSlash[subnetwork][operator].length() > 0) {
            return super.cumulativeSlash(subnetwork, operator);
        }
        return IBaseSlasher(_oldSlasher).cumulativeSlash(subnetwork, operator);
    }

    function _stake(bytes32 subnetwork, address operator, uint48 captureTimestamp, bytes memory hints)
        internal
        view
        override
        returns (uint256)
    {
        if (captureTimestamp >= _migrateTimestamp) {
            return super._stake(subnetwork, operator, captureTimestamp, hints);
        }
        return IUniversalDelegator(_oldDelegator).stakeAt(subnetwork, operator, captureTimestamp, hints);
    }

    function _slashableStake(bytes32 subnetwork, address operator, uint48 captureTimestamp, bytes memory hints)
        internal
        view
        override
        returns (uint256 slashableStake_, uint256 stakeAmount)
    {
        address delegator = IVaultV2(vault).delegator();
        if (captureTimestamp == 0) {
            slashableStake_ = IUniversalDelegator(delegator).stakeFor(subnetwork, operator, 0);
            return (slashableStake_, slashableStake_);
        }

        OuterSlashableStakeHints memory outerSlashableStakeHints;
        if (hints.length > 0) {
            outerSlashableStakeHints = abi.decode(hints, (OuterSlashableStakeHints));
        }

        uint96 groupIndex = IUniversalDelegator(delegator)
            .getSlotOfAt(subnetwork, operator, captureTimestamp, outerSlashableStakeHints.slotOfHints).getParentIndex()
            .getParentIndex();
        uint256 groupAllocatedAmount = IUniversalDelegator(delegator)
            .getAllocatedAt(
                groupIndex, captureTimestamp, type(uint48).max, outerSlashableStakeHints.groupAllocatedHints
            );
        (slashableStake_, stakeAmount) =
            super._slashableStake(subnetwork, operator, captureTimestamp, outerSlashableStakeHints.slashableStakeHints);
        slashableStake_ = Math.min(
            slashableStake_,
            groupAllocatedAmount
                - Math.min(
                    groupCumulativeSlash(groupIndex)
                        - groupCumulativeSlashAt(
                            groupIndex, captureTimestamp, outerSlashableStakeHints.groupCumulativeSlashFromHint
                        ),
                    groupAllocatedAmount
                )
        );
    }

    function migrate() public {
        if (IMigratableEntity(vault).version() != 3) {
            revert WrongMigrate();
        }
        address oldSlasher = IVaultV2(vault).slasher();
        uint64 oldSlasherType = IEntity(oldSlasher).TYPE();
        if (oldSlasherType == TYPE) {
            revert NotMigrating();
        }
        _migrateTimestamp = uint48(block.timestamp);
        _oldDelegator = IVaultV2(vault).delegator();
        _oldSlasher = oldSlasher;
        if (oldSlasherType == 1) {
            uint256 slashRequestsLength = IVetoSlasher(oldSlasher).slashRequestsLength();
            assembly ("memory-safe") {
                sstore(_slashRequests.slot, slashRequestsLength)
            }
        }
    }
}
