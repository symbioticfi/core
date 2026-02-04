// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {VaultV2} from "../vault/VaultV2.sol";
import {Entity} from "../common/Entity.sol";
import {StaticDelegateCallable} from "../common/StaticDelegateCallable.sol";

import {Checkpoints} from "../libraries/CheckpointsV2.sol";
import {Subnetwork} from "../libraries/Subnetwork.sol";
import {UniversalDelegatorIndex} from "../libraries/UniversalDelegatorIndex.sol";

import {IBaseDelegator} from "../../interfaces/delegator/IBaseDelegator.sol";
import {IBaseSlasher} from "../../interfaces/slasher/IBaseSlasher.sol";
import {IBurner} from "../../interfaces/slasher/IBurner.sol";
import {IEntity} from "../../interfaces/common/IEntity.sol";
import {IMigratableEntity} from "../../interfaces/common/IMigratableEntity.sol";
import {IRegistry} from "../../interfaces/common/IRegistry.sol";
import {IUniversalDelegator} from "../../interfaces/delegator/IUniversalDelegator.sol";
import {IUniversalSlasher} from "../../interfaces/slasher/IUniversalSlasher.sol";
import {INetworkMiddlewareService} from "../../interfaces/service/INetworkMiddlewareService.sol";
import {IVault} from "../../interfaces/vault/IVault.sol";
import {IVaultV2} from "../../interfaces/vault/IVaultV2.sol";
import {IVetoSlasher} from "../../interfaces/slasher/IVetoSlasher.sol";

import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {FixedPointMathLib as Math} from "@solady/src/utils/FixedPointMathLib.sol";
import {SafeCastLib as SafeCast} from "@solady/src/utils/SafeCastLib.sol";

contract UniversalSlasher is Entity, StaticDelegateCallable, ReentrancyGuardUpgradeable, IUniversalSlasher {
    using Math for uint256;
    using SafeCast for uint256;
    using Checkpoints for Checkpoints.Trace208;
    using Checkpoints for Checkpoints.Trace256;
    using Subnetwork for bytes32;
    using Subnetwork for address;
    using UniversalDelegatorIndex for uint96;

    /**
     * @inheritdoc IUniversalSlasher
     */
    uint256 public constant BURNER_GAS_LIMIT = 150_000;

    /**
     * @inheritdoc IUniversalSlasher
     */
    uint256 public constant BURNER_RESERVE = 20_000;

    address internal immutable VAULT_FACTORY;
    address internal immutable NETWORK_MIDDLEWARE_SERVICE;
    address internal immutable NETWORK_REGISTRY;

    /**
     * @inheritdoc IUniversalSlasher
     */
    address public vault;

    /**
     * @inheritdoc IUniversalSlasher
     */
    bool public isBurnerHook;

    /**
     * @inheritdoc IUniversalSlasher
     */
    mapping(bytes32 subnetwork => mapping(address operator => uint48 value)) public latestSlashedCaptureTimestamp;

    mapping(bytes32 subnetwork => mapping(address operator => Checkpoints.Trace256 amount)) internal _cumulativeSlash;

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
    ) Entity(slasherFactory, entityType) {
        VAULT_FACTORY = vaultFactory;
        NETWORK_MIDDLEWARE_SERVICE = networkMiddlewareService;
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

            request.resolver = IVetoSlasher(_oldSlasher).resolverAt(request.subnetwork, request.captureTimestamp, "");
            if (request.resolver != address(0)) {
                unchecked {
                    // TODO: remove it, or add comment regarding block.timestamp versus slashIndex
                    request.resolver =
                        IVetoSlasher(_oldSlasher).resolverAt(request.subnetwork, uint48(block.timestamp) - 1, "");
                }
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
    function cumulativeSlashAt(bytes32 subnetwork, address operator, uint48 timestamp, bytes memory hint)
        public
        view
        returns (uint256)
    {
        if (timestamp >= _migrateTimestamp) {
            return _cumulativeSlash[subnetwork][operator].upperLookupRecent(timestamp, hint);
        }
        return IBaseSlasher(_oldSlasher).cumulativeSlashAt(subnetwork, operator, timestamp, hint);
    }

    /**
     * @inheritdoc IUniversalSlasher
     */
    function cumulativeSlash(bytes32 subnetwork, address operator) public view returns (uint256) {
        if (_oldSlasher == address(0) || _cumulativeSlash[subnetwork][operator].length() > 0) {
            return _cumulativeSlash[subnetwork][operator].latest();
        }
        return IBaseSlasher(_oldSlasher).cumulativeSlash(subnetwork, operator);
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
    function slashableStake(bytes32 subnetwork, address operator, uint48 captureTimestamp, bytes memory hints)
        public
        view
        returns (uint256 slashableStake_)
    {
        (slashableStake_,) = _slashableStake(subnetwork, operator, captureTimestamp, hints);
    }

    function _slashableStake(bytes32 subnetwork, address operator, uint48 captureTimestamp, bytes memory hints)
        internal
        view
        returns (uint256 slashableStake_, uint96 groupIndex)
    {
        // forgefmt: disable-start
        // TODO: after slash without capture timestamp
        // bytes memory groupCumulativeSlashFromHint;
        // bytes memory cumulativeSlashFromHint; 
        bytes memory slotOfHints; bytes memory stakeHints; bytes memory groupAllocatedHints; 
        if (hints.length > 0) {
            (slotOfHints, stakeHints, groupAllocatedHints) = abi.decode(hints, (bytes, bytes, bytes));
        }
        // forgefmt: disable-end

        address delegator = IVaultV2(vault).delegator();
        if (captureTimestamp == 0) {
            return (
                IUniversalDelegator(delegator).stakeFor(subnetwork, operator, 0),
                IUniversalDelegator(delegator).getSlotOf(subnetwork, operator).getParentIndex().getParentIndex()
            );
        }

        if (
            captureTimestamp < uint256(uint48(block.timestamp)).saturatingSub(IVault(vault).epochDuration())
                || captureTimestamp >= uint48(block.timestamp)
                || captureTimestamp < latestSlashedCaptureTimestamp[subnetwork][operator]
        ) {
            return (0, 0);
        }

        unchecked {
            if (captureTimestamp >= _migrateTimestamp) {
                groupIndex = IUniversalDelegator(delegator)
                    .getSlotOfAt(subnetwork, operator, captureTimestamp, slotOfHints).getParentIndex().getParentIndex();

                slashableStake_ = Math.min(
                    IUniversalDelegator(delegator).stakeForAt(subnetwork, operator, 0, captureTimestamp, stakeHints)
                        .saturatingSub(
                            cumulativeSlash(subnetwork, operator)
                                - cumulativeSlashAt(subnetwork, operator, captureTimestamp, "")
                        ),
                    IUniversalDelegator(delegator).getAllocatedAt(groupIndex, captureTimestamp, 0, groupAllocatedHints)
                        .saturatingSub(
                            groupCumulativeSlash(groupIndex) - groupCumulativeSlashAt(groupIndex, captureTimestamp, "")
                        )
                );
            } else {
                slashableStake_ = IBaseDelegator(_oldDelegator).stakeAt(subnetwork, operator, captureTimestamp, "")
                    .saturatingSub(
                        cumulativeSlash(subnetwork, operator)
                            - cumulativeSlashAt(subnetwork, operator, captureTimestamp, "")
                    );
            }
        }
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
    ) public nonReentrant returns (uint256 slashIndex) {
        _checkNetworkMiddleware(subnetwork);

        address resolver = resolver(subnetwork);
        uint48 vetoDeadline = uint48(block.timestamp) + (resolver != address(0) ? vetoDuration : 0);
        if (
            captureTimestamp > 0
                && (captureTimestamp < uint256(vetoDeadline).saturatingSub(IVaultV2(vault).epochDuration())
                    || captureTimestamp >= uint48(block.timestamp))
        ) {
            revert InvalidCaptureTimestamp();
        }

        amount = Math.min(amount, slashableStake(subnetwork, operator, captureTimestamp, hints));
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
        SlashRequest memory request = slashRequests(slashIndex);

        _checkNetworkMiddleware(request.subnetwork);

        if (request.vetoDeadline > block.timestamp) {
            revert VetoPeriodNotEnded();
        }

        unchecked {
            // TODO: rework with full slashing without capture timestamp
            if (request.captureTimestamp == 0) {
                if (
                    block.timestamp - (request.vetoDeadline - (request.resolver == address(0) ? 0 : vetoDuration))
                        > IVaultV2(vault).epochDuration()
                ) {
                    revert SlashPeriodEnded();
                }
            } else if (block.timestamp - request.captureTimestamp > IVaultV2(vault).epochDuration()) {
                revert SlashPeriodEnded();
            }
        }

        if (request.completed) {
            revert SlashRequestCompleted();
        }

        // forgefmt: disable-start 
        bytes memory slashableStakeHints; bytes memory vaultOnSlashHints;
        if (hints.length > 0) {
            (slashableStakeHints, vaultOnSlashHints) = abi.decode(hints, (bytes, bytes));
        }
        // forgefmt: disable-end

        (uint256 slashableStake_, uint96 groupIndex) =
            _slashableStake(request.subnetwork, request.operator, request.captureTimestamp, slashableStakeHints);
        slashedAmount = Math.min(request.amount, slashableStake_);
        if (slashedAmount == 0) {
            revert InsufficientSlash();
        }

        _slashRequests[slashIndex].completed = true;

        if (request.captureTimestamp == 0) {
            request.captureTimestamp = uint48(block.timestamp);
        }
        latestSlashedCaptureTimestamp[request.subnetwork][request.operator] = request.captureTimestamp;
        _cumulativeSlash[request.subnetwork][request.operator].push(
            uint48(block.timestamp), cumulativeSlash(request.subnetwork, request.operator) + slashedAmount
        );
        _groupCumulativeSlash[groupIndex].push(
            uint48(block.timestamp), groupCumulativeSlash(groupIndex) + slashedAmount
        );

        unchecked {
            uint256 owed_;
            (slashedAmount, owed_) = VaultV2(vault).onSlash(slashedAmount, vaultOnSlashHints);
            if (owed_ > 0) {
                owed[request.subnetwork][request.operator][request.captureTimestamp] += owed_;
            }
        }

        // TODO: do hook for legacy
        IUniversalDelegator(IVault(vault).delegator())
            .onSlash(
                request.subnetwork, request.operator, slashedAmount, request.captureTimestamp, abi.encode(slashIndex)
            );

        _burnerOnSlash(request.subnetwork, request.operator, slashedAmount, request.captureTimestamp);

        emit ExecuteSlash(slashIndex, slashedAmount);
    }

    /**
     * @inheritdoc IUniversalSlasher
     */
    function vetoSlash(uint256 slashIndex) public nonReentrant {
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
    function setResolver(uint96 identifier, address newResolver) public nonReentrant {
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

    /**
     * @inheritdoc IUniversalSlasher
     */
    function syncOwedSlash(bytes32 subnetwork, address operator, uint48 captureTimestamp)
        public
        returns (uint256 slashed)
    {
        unchecked {
            uint256 owed_ = owed[subnetwork][operator][captureTimestamp];
            slashed = VaultV2(vault).syncOwedSlash(owed_);
            owed[subnetwork][operator][captureTimestamp] = owed_ - slashed;
            _burnerOnSlash(subnetwork, operator, slashed, captureTimestamp);

            emit SyncOwedSlash(subnetwork, operator, captureTimestamp, slashed);
        }
    }

    function _checkNetworkMiddleware(bytes32 subnetwork) internal view {
        if (INetworkMiddlewareService(NETWORK_MIDDLEWARE_SERVICE).middleware(subnetwork.network()) != msg.sender) {
            revert NotNetworkMiddleware();
        }
    }

    function _burnerOnSlash(bytes32 subnetwork, address operator, uint256 amount, uint48 captureTimestamp) internal {
        unchecked {
            if (isBurnerHook) {
                address burner = IVault(vault).burner();
                bytes memory calldata_ =
                    abi.encodeCall(IBurner.onSlash, (subnetwork, operator, amount, captureTimestamp));

                if (gasleft() < BURNER_RESERVE + BURNER_GAS_LIMIT * 64 / 63) {
                    revert InsufficientBurnerGas();
                }

                assembly ("memory-safe") {
                    pop(call(BURNER_GAS_LIMIT, burner, 0, add(calldata_, 0x20), mload(calldata_), 0, 0))
                }
            }
        }
    }

    function _initialize(bytes calldata data) internal override {
        (address vault_, bytes memory data_) = abi.decode(data, (address, bytes));

        if (!IRegistry(VAULT_FACTORY).isEntity(vault_)) {
            revert NotVault();
        }

        if (IMigratableEntity(vault_).version() < 3) {
            revert OldVault();
        }

        InitParams memory params = abi.decode(data_, (InitParams));

        if (params.vetoDuration >= IVaultV2(vault_).epochDuration()) {
            revert InvalidVetoDuration();
        }

        if (params.resolverSetDelay <= IVaultV2(vault_).epochDuration()) {
            revert InvalidResolverSetEpochsDelay();
        }

        if (IVault(vault_).burner() == address(0) && params.isBurnerHook) {
            revert NoBurner();
        }

        __ReentrancyGuard_init();

        vault = vault_;

        isBurnerHook = params.isBurnerHook;
        vetoDuration = params.vetoDuration;
        resolverSetDelay = params.resolverSetDelay;

        emit Initialize(params);
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
