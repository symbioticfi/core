// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Entity} from "../common/Entity.sol";
import {StaticDelegateCallable} from "../common/StaticDelegateCallable.sol";

import {IBaseDelegator} from "../../interfaces/delegator/IBaseDelegator.sol";
import {IBaseSlasher} from "../../interfaces/slasher/IBaseSlasher.sol";
import {IBurner} from "../../interfaces/slasher/IBurner.sol";
import {INetworkMiddlewareService} from "../../interfaces/service/INetworkMiddlewareService.sol";
import {IRegistry} from "../../interfaces/common/IRegistry.sol";
import {IVault} from "../../interfaces/vault/IVault.sol";

import {Checkpoints} from "../libraries/Checkpoints.sol";
import {Subnetwork} from "../libraries/Subnetwork.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

abstract contract BaseSlasher is Entity, StaticDelegateCallable, ReentrancyGuardUpgradeable, IBaseSlasher {
    using Checkpoints for Checkpoints.Trace256;
    using Subnetwork for bytes32;

    /**
     * @inheritdoc IBaseSlasher
     */
    uint256 public constant BURNER_GAS_LIMIT = 150_000;

    /**
     * @inheritdoc IBaseSlasher
     */
    uint256 public constant BURNER_RESERVE = 20_000;

    /**
     * @inheritdoc IBaseSlasher
     */
    address public immutable VAULT_FACTORY;

    /**
     * @inheritdoc IBaseSlasher
     */
    address public immutable NETWORK_MIDDLEWARE_SERVICE;

    /**
     * @inheritdoc IBaseSlasher
     */
    address public vault;

    /**
     * @inheritdoc IBaseSlasher
     */
    bool public isBurnerHook;

    /**
     * @inheritdoc IBaseSlasher
     */
    mapping(bytes32 subnetwork => mapping(address operator => uint48 value)) public latestSlashedCaptureTimestamp;

    mapping(bytes32 subnetwork => mapping(address operator => Checkpoints.Trace256 amount)) internal _cumulativeSlash;

    modifier onlyNetworkMiddleware(
        bytes32 subnetwork
    ) {
        _checkNetworkMiddleware(subnetwork);

        _;
    }

    constructor(
        address vaultFactory,
        address networkMiddlewareService,
        address slasherFactory,
        uint64 entityType
    ) Entity(slasherFactory, entityType) {
        VAULT_FACTORY = vaultFactory;
        NETWORK_MIDDLEWARE_SERVICE = networkMiddlewareService;
    }

    /**
     * @inheritdoc IBaseSlasher
     */
    function cumulativeSlashAt(
        bytes32 subnetwork,
        address operator,
        uint48 timestamp,
        bytes memory hint
    ) public view returns (uint256) {
        return _cumulativeSlash[subnetwork][operator].upperLookupRecent(timestamp, hint);
    }

    /**
     * @inheritdoc IBaseSlasher
     */
    function cumulativeSlash(bytes32 subnetwork, address operator) public view returns (uint256) {
        return _cumulativeSlash[subnetwork][operator].latest();
    }

    /**
     * @inheritdoc IBaseSlasher
     */
    function slashableStake(
        bytes32 subnetwork,
        address operator,
        uint48 captureTimestamp,
        bytes memory hints
    ) public view returns (uint256 amount) {
        (amount,) = _slashableStake(subnetwork, operator, captureTimestamp, hints);
    }

    function _slashableStake(
        bytes32 subnetwork,
        address operator,
        uint48 captureTimestamp,
        bytes memory hints
    ) internal view returns (uint256 slashableStake_, uint256 stakeAmount) {
        SlashableStakeHints memory slashableStakeHints;
        if (hints.length > 0) {
            slashableStakeHints = abi.decode(hints, (SlashableStakeHints));
        }

        if (
            captureTimestamp < Time.timestamp() - IVault(vault).epochDuration() || captureTimestamp >= Time.timestamp()
                || captureTimestamp < latestSlashedCaptureTimestamp[subnetwork][operator]
        ) {
            return (0, 0);
        }

        stakeAmount = IBaseDelegator(IVault(vault).delegator()).stakeAt(
            subnetwork, operator, captureTimestamp, slashableStakeHints.stakeHints
        );
        slashableStake_ = stakeAmount
            - Math.min(
                cumulativeSlash(subnetwork, operator)
                    - cumulativeSlashAt(subnetwork, operator, captureTimestamp, slashableStakeHints.cumulativeSlashFromHint),
                stakeAmount
            );
    }

    function _checkNetworkMiddleware(
        bytes32 subnetwork
    ) internal view {
        if (INetworkMiddlewareService(NETWORK_MIDDLEWARE_SERVICE).middleware(subnetwork.network()) != msg.sender) {
            revert NotNetworkMiddleware();
        }
    }

    function _updateLatestSlashedCaptureTimestamp(
        bytes32 subnetwork,
        address operator,
        uint48 captureTimestamp
    ) internal {
        if (latestSlashedCaptureTimestamp[subnetwork][operator] < captureTimestamp) {
            latestSlashedCaptureTimestamp[subnetwork][operator] = captureTimestamp;
        }
    }

    function _updateCumulativeSlash(bytes32 subnetwork, address operator, uint256 amount) internal {
        _cumulativeSlash[subnetwork][operator].push(Time.timestamp(), cumulativeSlash(subnetwork, operator) + amount);
    }

    function _delegatorOnSlash(
        bytes32 subnetwork,
        address operator,
        uint256 amount,
        uint48 captureTimestamp,
        bytes memory data
    ) internal {
        IBaseDelegator(IVault(vault).delegator()).onSlash(
            subnetwork,
            operator,
            amount,
            captureTimestamp,
            abi.encode(GeneralDelegatorData({slasherType: TYPE, data: data}))
        );
    }

    function _vaultOnSlash(uint256 amount, uint48 captureTimestamp) internal {
        IVault(vault).onSlash(amount, captureTimestamp);
    }

    function _burnerOnSlash(bytes32 subnetwork, address operator, uint256 amount, uint48 captureTimestamp) internal {
        if (isBurnerHook) {
            address burner = IVault(vault).burner();
            bytes memory calldata_ = abi.encodeCall(IBurner.onSlash, (subnetwork, operator, amount, captureTimestamp));

            if (gasleft() < BURNER_RESERVE + BURNER_GAS_LIMIT * 64 / 63) {
                revert InsufficientBurnerGas();
            }

            assembly ("memory-safe") {
                pop(call(BURNER_GAS_LIMIT, burner, 0, add(calldata_, 0x20), mload(calldata_), 0, 0))
            }
        }
    }

    function _initialize(
        bytes calldata data
    ) internal override {
        (address vault_, bytes memory data_) = abi.decode(data, (address, bytes));

        if (!IRegistry(VAULT_FACTORY).isEntity(vault_)) {
            revert NotVault();
        }

        __ReentrancyGuard_init();

        vault = vault_;

        BaseParams memory baseParams = __initialize(vault_, data_);

        if (IVault(vault_).burner() == address(0) && baseParams.isBurnerHook) {
            revert NoBurner();
        }

        isBurnerHook = baseParams.isBurnerHook;
    }

    function __initialize(address vault_, bytes memory data) internal virtual returns (BaseParams memory) {}
}
