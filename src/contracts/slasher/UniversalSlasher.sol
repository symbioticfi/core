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
import {INetworkMiddlewareService} from "../../interfaces/service/INetworkMiddlewareService.sol";
import {IRegistry} from "../../interfaces/common/IRegistry.sol";
import {IUniversalDelegator} from "../../interfaces/delegator/IUniversalDelegator.sol";
import {IUniversalSlasher, BURNER_GAS_LIMIT, BURNER_RESERVE} from "../../interfaces/slasher/IUniversalSlasher.sol";
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
    uint48 public vetoDuration; // TODO: move from legacy

    /**
     * @inheritdoc IUniversalSlasher
     */
    uint48 public resolverSetDelay;

    SlashRequest[] internal _slashRequests;

    mapping(bytes32 subnetwork => mapping(address operator => uint256 amount)) public owed;

    mapping(bytes32 subnetwork => address value) internal _resolver;

    mapping(bytes32 subnetwork => uint256 value) public pendingResolverData;

    mapping(bytes32 subnetwork => mapping(address operator => uint48 value)) internal __latestSlashedCaptureTimestamp;

    mapping(bytes32 subnetwork => mapping(address operator => Checkpoints.Trace256 amount)) internal __cumulativeSlash;

    uint48 internal __migrateTimestamp;

    address internal __oldDelegator;

    address internal __oldSlasher;

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
            (request.subnetwork, request.operator, request.amount, request.createdAt, request.vetoDeadline,) =
                IVetoSlasher(__oldSlasher).slashRequests(slashIndex);

            request.resolver = IVetoSlasher(__oldSlasher).resolverAt(request.subnetwork, request.createdAt, "");
            if (request.resolver != address(0)) {
                unchecked {
                    // TODO: remove it, or add comment regarding block.timestamp versus slashIndex
                    request.resolver =
                        IVetoSlasher(__oldSlasher).resolverAt(request.subnetwork, uint48(block.timestamp) - 1, "");
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
    function slashableStake(bytes32 subnetwork, address operator, uint48 captureTimestamp, bytes memory)
        public
        view
        returns (uint256)
    {
        unchecked {
            if (captureTimestamp == 0 || captureTimestamp >= __migrateTimestamp) {
                return IUniversalDelegator(IVaultV2(vault).delegator()).stakeFor(subnetwork, operator, 0);
            } else {
                if (
                    captureTimestamp < uint256(uint48(block.timestamp)).saturatingSub(IVault(vault).epochDuration())
                        || captureTimestamp >= uint48(block.timestamp)
                        || captureTimestamp < _latestSlashedCaptureTimestamp(subnetwork, operator)
                ) {
                    return 0;
                }
                return IBaseDelegator(__oldDelegator).stakeAt(subnetwork, operator, captureTimestamp, "")
                    .saturatingSub(
                        _cumulativeSlash(subnetwork, operator)
                            - _cumulativeSlashAt(subnetwork, operator, captureTimestamp)
                    );
            }
        }
    }

    /**
     * @inheritdoc IUniversalSlasher
     */
    function requestSlash(bytes32 subnetwork, address operator, uint256 amount, uint48, bytes calldata hints)
        public
        nonReentrant
        returns (uint256 slashIndex)
    {
        _checkNetworkMiddleware(subnetwork);

        amount = Math.min(amount, slashableStake(subnetwork, operator, 0, hints));
        if (amount == 0) {
            revert InsufficientSlash();
        }

        address resolver = resolver(subnetwork);
        uint48 vetoDeadline = uint48(block.timestamp) + (resolver != address(0) ? vetoDuration : 0);

        slashIndex = _slashRequests.length;
        _slashRequests.push(
            SlashRequest({
                subnetwork: subnetwork,
                operator: operator,
                amount: amount,
                createdAt: uint48(block.timestamp),
                resolver: resolver,
                vetoDeadline: vetoDeadline,
                completed: false
            })
        );

        emit RequestSlash(slashIndex, subnetwork, operator, amount, vetoDeadline);
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
            if (block.timestamp - request.createdAt > IVaultV2(vault).epochDuration()) {
                revert SlashPeriodEnded();
            }
        }

        if (request.completed) {
            revert SlashRequestCompleted();
        }

        slashedAmount =
            Math.min(request.amount, slashableStake(request.subnetwork, request.operator, request.createdAt, ""));
        if (slashedAmount == 0) {
            revert InsufficientSlash();
        }

        _slashRequests[slashIndex].completed = true;

        if (request.createdAt < __migrateTimestamp) {
            __latestSlashedCaptureTimestamp[request.subnetwork][request.operator] = request.createdAt;
            __cumulativeSlash[request.subnetwork][request.operator].push(
                uint48(block.timestamp), _cumulativeSlash(request.subnetwork, request.operator) + slashedAmount
            );
        } else {
            IUniversalDelegator(IVault(vault).delegator())
                .onSlash(request.subnetwork, request.operator, slashedAmount, request.createdAt, abi.encode(slashIndex));
        }

        unchecked {
            uint256 owed_;
            (slashedAmount, owed_) = VaultV2(vault).onSlash(slashedAmount, hints);
            if (owed_ > 0) {
                owed[request.subnetwork][request.operator] += owed_;
            }
        }

        _burnerOnSlash(request.subnetwork, request.operator, slashedAmount);

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

        if (request.vetoDeadline <= block.timestamp) {
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
    function syncOwedSlash(bytes32 subnetwork, address operator) public returns (uint256 slashed) {
        unchecked {
            uint256 owed_ = owed[subnetwork][operator];
            slashed = VaultV2(vault).syncOwedSlash(owed_);
            owed[subnetwork][operator] = owed_ - slashed;
            _burnerOnSlash(subnetwork, operator, slashed);

            emit SyncOwedSlash(subnetwork, operator, slashed);
        }
    }

    function _checkNetworkMiddleware(bytes32 subnetwork) internal view {
        if (INetworkMiddlewareService(NETWORK_MIDDLEWARE_SERVICE).middleware(subnetwork.network()) != msg.sender) {
            revert NotNetworkMiddleware();
        }
    }

    function _burnerOnSlash(bytes32 subnetwork, address operator, uint256 amount) internal {
        unchecked {
            if (isBurnerHook) {
                address burner = IVault(vault).burner();
                bytes memory calldata_ = abi.encodeCall(IBurner.onSlash, (subnetwork, operator, amount, 0));

                if (gasleft() < BURNER_RESERVE + BURNER_GAS_LIMIT * 64 / 63) {
                    revert InsufficientBurnerGas();
                }

                assembly ("memory-safe") {
                    pop(call(BURNER_GAS_LIMIT, burner, 0, add(calldata_, 0x20), mload(calldata_), 0, 0))
                }
            }
        }
    }

    function _latestSlashedCaptureTimestamp(bytes32 subnetwork, address operator) internal view returns (uint48) {
        if (__oldSlasher == address(0) || __latestSlashedCaptureTimestamp[subnetwork][operator] > 0) {
            return __latestSlashedCaptureTimestamp[subnetwork][operator];
        }
        return IBaseSlasher(__oldSlasher).latestSlashedCaptureTimestamp(subnetwork, operator);
    }

    /// @dev to support legacy
    function _cumulativeSlashAt(bytes32 subnetwork, address operator, uint48 timestamp)
        internal
        view
        returns (uint256)
    {
        if (timestamp >= __migrateTimestamp) {
            return __cumulativeSlash[subnetwork][operator].upperLookupRecent(timestamp);
        }
        return IBaseSlasher(__oldSlasher).cumulativeSlashAt(subnetwork, operator, timestamp, "");
    }

    function _cumulativeSlash(bytes32 subnetwork, address operator) internal view returns (uint256) {
        if (__oldSlasher == address(0) || __cumulativeSlash[subnetwork][operator].length() > 0) {
            return __cumulativeSlash[subnetwork][operator].latest();
        }
        return IBaseSlasher(__oldSlasher).cumulativeSlash(subnetwork, operator);
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
        __migrateTimestamp = uint48(block.timestamp);
        __oldDelegator = IVaultV2(vault).delegator();
        __oldSlasher = oldSlasher;
        if (oldSlasherType == 1) {
            uint256 slashRequestsLength = IVetoSlasher(oldSlasher).slashRequestsLength();
            assembly ("memory-safe") {
                sstore(_slashRequests.slot, slashRequestsLength)
            }
        }
    }
}
