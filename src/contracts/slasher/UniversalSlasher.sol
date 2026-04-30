// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Entity} from "../common/Entity.sol";
import {StaticDelegateCallable} from "../common/StaticDelegateCallable.sol";
import {UniversalDelegator} from "../delegator/UniversalDelegator.sol";
import {VaultV2} from "../vault/VaultV2.sol";

import {Checkpoints} from "../libraries/CheckpointsV2.sol";
import {Subnetwork} from "../libraries/Subnetwork.sol";

import {IBaseSlasher} from "../../interfaces/slasher/IBaseSlasher.sol";
import {IBurner} from "../../interfaces/slasher/IBurner.sol";
import {IEntity} from "../../interfaces/common/IEntity.sol";
import {IMigratableEntity} from "../../interfaces/common/IMigratableEntity.sol";
import {INetworkMiddlewareService} from "../../interfaces/service/INetworkMiddlewareService.sol";
import {IRegistry} from "../../interfaces/common/IRegistry.sol";
import {IUniversalSlasher, BURNER_GAS_LIMIT, BURNER_RESERVE} from "../../interfaces/slasher/IUniversalSlasher.sol";
import {IVetoSlasher, VETO_SLASHER_TYPE} from "../../interfaces/slasher/IVetoSlasher.sol";
import {VAULT_V2_VERSION, MAX_DURATION} from "../../interfaces/vault/IVaultV2.sol";

import {Calldata} from "@openzeppelin/contracts/utils/Calldata.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {FixedPointMathLib as Math} from "@solady/src/utils/FixedPointMathLib.sol";

/// @title UniversalSlasher
/// @notice Contract for slash request lifecycle, resolver updates, and owed slash synchronization.
contract UniversalSlasher is Entity, StaticDelegateCallable, ReentrancyGuardUpgradeable, IUniversalSlasher {
    using Math for uint256;
    using Subnetwork for bytes32;
    using Subnetwork for address;
    using Checkpoints for Checkpoints.Trace208;
    using Checkpoints for Checkpoints.Trace256;

    /* IMMUTABLES */

    /// @dev Address of the vault factory.
    address internal immutable VAULT_FACTORY;
    /// @dev Address of the network middleware service.
    address internal immutable NETWORK_MIDDLEWARE_SERVICE;
    /// @dev Address of the network registry.
    address internal immutable NETWORK_REGISTRY;

    /* STATE VARIABLES */

    /// @inheritdoc IUniversalSlasher
    address public vault;
    /// @inheritdoc IUniversalSlasher
    bool public isBurnerHook;
    /// @inheritdoc IUniversalSlasher
    uint48 public vetoDuration;
    /// @inheritdoc IUniversalSlasher
    uint48 public resolverSetDelay;
    /// @inheritdoc IUniversalSlasher
    mapping(bytes32 subnetwork => bool) public isResolverSet;
    /// @inheritdoc IUniversalSlasher
    mapping(bytes32 subnetwork => bytes32 value) public pendingResolverData;

    /// @inheritdoc IUniversalSlasher
    uint256 public totalOwed;
    /// @inheritdoc IUniversalSlasher
    mapping(bytes32 subnetwork => mapping(address operator => uint256 amount)) public owed;

    /// @dev Slash request storage.
    SlashRequest[] internal _slashRequests;
    /// @dev Active resolver per subnetwork.
    mapping(bytes32 subnetwork => address value) internal _resolver;
    /// @dev Legacy latest slashed capture timestamps.
    mapping(bytes32 subnetwork => mapping(address operator => uint48 value)) internal __latestSlashedCaptureTimestamp;
    /// @dev Legacy cumulative slash checkpoints.
    mapping(bytes32 subnetwork => mapping(address operator => Checkpoints.Trace256 amount)) internal __cumulativeSlash;

    /// @inheritdoc IUniversalSlasher
    uint48 public migrateTimestamp;
    /// @inheritdoc IUniversalSlasher
    address public oldSlasher;

    /* CONSTRUCTOR */

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

    /* VIEW FUNCTIONS */

    /// @inheritdoc IUniversalSlasher
    function slashRequestsLength() public view returns (uint256) {
        return _slashRequests.length;
    }

    /// @inheritdoc IUniversalSlasher
    function slashRequests(uint256 slashIndex) public view returns (SlashRequest memory request) {
        request = _slashRequests[slashIndex];

        // Legacy support.
        if (request.amount == 0) {
            bool oldCompleted;
            (
                request.subnetwork,
                request.operator,
                request.amount,
                request.createdAt,
                request.vetoDeadline,
                oldCompleted
            ) = IVetoSlasher(oldSlasher).slashRequests(slashIndex);
            if (oldCompleted) {
                request.completed = true;
            }
            request.resolver = IVetoSlasher(oldSlasher).resolverAt(request.subnetwork, request.createdAt, "");
            if (
                request.resolver != address(0)
                    && IVetoSlasher(oldSlasher).resolverAt(request.subnetwork, uint48(block.timestamp) - 1, "")
                        == address(0)
            ) {
                request.resolver = address(0);
            }
        }
    }

    /// @inheritdoc IUniversalSlasher
    function resolver(bytes32 subnetwork) public view returns (address) {
        // Legacy support.
        if (!isResolverSet[subnetwork] && oldSlasher != address(0) && IEntity(oldSlasher).TYPE() == VETO_SLASHER_TYPE) {
            return IVetoSlasher(oldSlasher).resolver(subnetwork, "");
        }
        return uint48(uint256(pendingResolverData[subnetwork])) == 0
            || block.timestamp < uint48(uint256(pendingResolverData[subnetwork]))
            ? _resolver[subnetwork]
            : address(uint160(uint256(pendingResolverData[subnetwork]) >> 48));
    }

    /// @inheritdoc IUniversalSlasher
    function slashableStake(bytes32 subnetwork, address operator, uint48 captureTimestamp, bytes calldata)
        public
        view
        returns (uint256)
    {
        if (captureTimestamp == 0 || captureTimestamp >= migrateTimestamp) {
            if (
                captureTimestamp > 0
                    && (captureTimestamp <= block.timestamp.saturatingSub(VaultV2(vault).epochDuration())
                        || captureTimestamp > block.timestamp)
            ) {
                return 0;
            }
            return UniversalDelegator(VaultV2(vault).delegator()).stakeFor(subnetwork, operator, 0);
        }

        // Legacy support.
        if (
            captureTimestamp <= block.timestamp.saturatingSub(VaultV2(vault).epochDuration())
                || captureTimestamp >= block.timestamp
                || captureTimestamp < _latestSlashedCaptureTimestamp(subnetwork, operator)
        ) {
            return 0;
        }
        return UniversalDelegator(VaultV2(vault).delegator()).stakeAt(subnetwork, operator, captureTimestamp, "")
            .saturatingSub(
                _cumulativeSlash(subnetwork, operator) - _cumulativeSlashAt(subnetwork, operator, captureTimestamp)
            );
    }

    /* PUBLIC FUNCTIONS */

    /// @inheritdoc IUniversalSlasher
    function slash(bytes32 subnetwork, address operator, uint256 amount, uint48, bytes calldata)
        external
        returns (uint256)
    {
        return executeSlash(requestSlash(subnetwork, operator, amount, 0, Calldata.emptyBytes()), Calldata.emptyBytes());
    }

    /// @inheritdoc IUniversalSlasher
    function requestSlash(bytes32 subnetwork, address operator, uint256 amount, uint48, bytes calldata)
        public
        nonReentrant
        returns (uint256 slashIndex)
    {
        _checkNetworkMiddleware(subnetwork);

        amount = Math.min(amount, slashableStake(subnetwork, operator, 0, Calldata.emptyBytes()));
        if (amount == 0) {
            revert InsufficientSlash();
        }

        address curResolver = resolver(subnetwork);
        uint48 vetoDeadline = uint48(block.timestamp) + (curResolver != address(0) ? vetoDuration : 0);

        slashIndex = _slashRequests.length;
        _slashRequests.push(
            SlashRequest({
                subnetwork: subnetwork,
                operator: operator,
                amount: amount,
                createdAt: uint48(block.timestamp),
                resolver: curResolver,
                vetoDeadline: vetoDeadline,
                completed: false
            })
        );

        emit RequestSlash(slashIndex, subnetwork, operator, amount, vetoDeadline);
    }

    /// @inheritdoc IUniversalSlasher
    function executeSlash(uint256 slashIndex, bytes calldata) public nonReentrant returns (uint256 slashedAmount) {
        SlashRequest memory request = slashRequests(slashIndex);

        _checkNetworkMiddleware(request.subnetwork);

        if (request.completed) {
            revert SlashRequestCompleted();
        }

        if (request.vetoDeadline > block.timestamp) {
            revert VetoPeriodNotEnded();
        }

        slashedAmount = Math.min(
            request.amount,
            slashableStake(request.subnetwork, request.operator, request.createdAt, Calldata.emptyBytes())
        );
        if (slashedAmount == 0) {
            revert InsufficientSlash();
        }

        _slashRequests[slashIndex].completed = true;

        UniversalDelegator delegator = UniversalDelegator(VaultV2(vault).delegator());
        if (request.createdAt >= migrateTimestamp) {
            delegator.onSlash(request.subnetwork, request.operator, slashedAmount);
        } else {
            // Legacy support.
            __latestSlashedCaptureTimestamp[request.subnetwork][request.operator] = request.createdAt;
            __cumulativeSlash[request.subnetwork][request.operator].push(
                uint48(block.timestamp), _cumulativeSlash(request.subnetwork, request.operator) + slashedAmount
            );
            delegator.onSlashLegacy(request.subnetwork, request.operator, slashedAmount);
        }

        uint256 owedAmount;
        (slashedAmount, owedAmount) = VaultV2(vault).onSlash(slashedAmount);
        if (owedAmount > 0) {
            totalOwed += owedAmount;
            owed[request.subnetwork][request.operator] += owedAmount;
        }

        _burnerOnSlash(request.subnetwork, request.operator, slashedAmount - owedAmount);

        emit ExecuteSlash(slashIndex, slashedAmount);
    }

    /// @inheritdoc IUniversalSlasher
    function vetoSlash(uint256 slashIndex) public nonReentrant {
        SlashRequest memory request = slashRequests(slashIndex);

        if (request.completed) {
            revert SlashRequestCompleted();
        }

        if (request.resolver != msg.sender) {
            revert NotResolver();
        }

        if (request.vetoDeadline <= block.timestamp) {
            revert VetoPeriodEnded();
        }

        _slashRequests[slashIndex].completed = true;

        emit VetoSlash(slashIndex, msg.sender);
    }

    /// @inheritdoc IUniversalSlasher
    function setResolver(uint96 identifier, address newResolver) public nonReentrant {
        if (!IRegistry(NETWORK_REGISTRY).isEntity(msg.sender)) {
            revert NotNetwork();
        }

        bytes32 subnetwork = (msg.sender).subnetwork(identifier);
        address curResolver = resolver(subnetwork);

        // Legacy support.
        isResolverSet[subnetwork] = true;
        if (curResolver == address(0)) {
            _resolver[subnetwork] = newResolver;
            pendingResolverData[subnetwork] = 0;
        } else {
            _resolver[subnetwork] = curResolver;
            pendingResolverData[subnetwork] =
                bytes32(uint256(uint160(newResolver)) << 48 | (block.timestamp + resolverSetDelay));
        }

        emit SetResolver(subnetwork, newResolver);
    }

    /* PUBLIC FUNCTIONS (PERMISSIONLESS) */

    /// @inheritdoc IUniversalSlasher
    function syncOwedSlash(bytes32 subnetwork, address operator) public returns (uint256 slashedAmount) {
        uint256 curOwed = owed[subnetwork][operator];
        slashedAmount = VaultV2(vault).syncOwedSlash(curOwed);
        owed[subnetwork][operator] = curOwed - slashedAmount;
        totalOwed -= slashedAmount;
        _burnerOnSlash(subnetwork, operator, slashedAmount);

        emit SyncOwedSlash(subnetwork, operator, slashedAmount);
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Revert unless caller is the middleware configured for the request subnetwork.
    function _checkNetworkMiddleware(bytes32 subnetwork) internal view {
        if (INetworkMiddlewareService(NETWORK_MIDDLEWARE_SERVICE).middleware(subnetwork.network()) != msg.sender) {
            revert NotNetworkMiddleware();
        }
    }

    /// @dev Call the burner hook after a slash when burner hook mode is enabled.
    function _burnerOnSlash(bytes32 subnetwork, address operator, uint256 amount) internal {
        if (isBurnerHook) {
            address burner = VaultV2(vault).burner();
            bytes memory burnerCalldata = abi.encodeCall(IBurner.onSlash, (subnetwork, operator, amount, 0));

            if (gasleft() < BURNER_RESERVE + BURNER_GAS_LIMIT * 64 / 63) {
                revert InsufficientBurnerGas();
            }

            assembly ("memory-safe") {
                pop(call(BURNER_GAS_LIMIT, burner, 0, add(burnerCalldata, 0x20), mload(burnerCalldata), 0, 0))
            }
        }
    }

    /* INITIALIZATION */

    /// @dev Initialize slasher state from encoded initialization parameters.
    function _initialize(bytes calldata data) internal override {
        (address initVault, bytes memory initData) = abi.decode(data, (address, bytes));

        if (!IRegistry(VAULT_FACTORY).isEntity(initVault)) {
            revert NotVault();
        }

        if (IMigratableEntity(initVault).version() < VAULT_V2_VERSION) {
            revert OldVault();
        }

        InitParams memory params = abi.decode(initData, (InitParams));

        if (params.vetoDuration >= VaultV2(initVault).epochDuration()) {
            revert InvalidVetoDuration();
        }

        if (params.resolverSetDelay <= VaultV2(initVault).epochDuration() || params.resolverSetDelay > MAX_DURATION) {
            revert InvalidResolverSetEpochsDelay();
        }

        if (VaultV2(initVault).burner() == address(0) && params.isBurnerHook) {
            revert NoBurner();
        }

        __ReentrancyGuard_init();

        vault = initVault;

        isBurnerHook = params.isBurnerHook;
        vetoDuration = params.vetoDuration;
        resolverSetDelay = params.resolverSetDelay;

        emit Initialize(params);
    }

    /* MIGRATION */

    /// @dev Migrate slasher state from the previously configured slasher.
    function migrate(address oldSlasher_) public {
        if (vault != msg.sender) {
            revert NotVault();
        }
        uint64 oldSlasherType = IEntity(oldSlasher_).TYPE();
        if (oldSlasherType == TYPE) {
            revert NotMigrating();
        }
        migrateTimestamp = uint48(block.timestamp);
        oldSlasher = oldSlasher_;

        isBurnerHook = IVetoSlasher(oldSlasher_).isBurnerHook();
        if (oldSlasherType == VETO_SLASHER_TYPE) {
            uint256 oldSlashRequestsLength = IVetoSlasher(oldSlasher_).slashRequestsLength();
            assembly ("memory-safe") {
                sstore(_slashRequests.slot, oldSlashRequestsLength)
            }
            vetoDuration = IVetoSlasher(oldSlasher_).vetoDuration();
            resolverSetDelay = uint48(
                Math.min(
                    IVetoSlasher(oldSlasher_).resolverSetEpochsDelay() * VaultV2(vault).epochDuration(), MAX_DURATION
                )
            );
        }
    }

    /* INTERNAL FUNCTIONS (LEGACY) */

    /// @dev Legacy support.
    function _latestSlashedCaptureTimestamp(bytes32 subnetwork, address operator) internal view returns (uint48) {
        if (oldSlasher == address(0) || __latestSlashedCaptureTimestamp[subnetwork][operator] > 0) {
            return __latestSlashedCaptureTimestamp[subnetwork][operator];
        }
        return IBaseSlasher(oldSlasher).latestSlashedCaptureTimestamp(subnetwork, operator);
    }

    /// @dev Legacy support.
    function _cumulativeSlashAt(bytes32 subnetwork, address operator, uint48 timestamp)
        internal
        view
        returns (uint256)
    {
        if (timestamp < migrateTimestamp) {
            return IBaseSlasher(oldSlasher).cumulativeSlashAt(subnetwork, operator, timestamp, "");
        }
        return __cumulativeSlash[subnetwork][operator].upperLookupRecent(timestamp);
    }

    /// @dev Legacy support.
    function _cumulativeSlash(bytes32 subnetwork, address operator) internal view returns (uint256) {
        if (oldSlasher == address(0) || __cumulativeSlash[subnetwork][operator].length() > 0) {
            return __cumulativeSlash[subnetwork][operator].latest();
        }
        return IBaseSlasher(oldSlasher).cumulativeSlash(subnetwork, operator);
    }
}
