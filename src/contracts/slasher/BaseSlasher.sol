// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Entity} from "../common/Entity.sol";
import {StaticDelegateCallable} from "../common/StaticDelegateCallable.sol";

import {IBaseDelegator} from "../../interfaces/delegator/IBaseDelegator.sol";
import {IBaseSlasher} from "../../interfaces/slasher/IBaseSlasher.sol";
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
    mapping(bytes32 subnetwork => uint48 value) public latestSlashedCaptureTimestamp;

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
    ) public view returns (uint256) {
        SlashableStakeHints memory slashableStakeHints;
        if (hints.length > 0) {
            slashableStakeHints = abi.decode(hints, (SlashableStakeHints));
        }

        if (captureTimestamp < Time.timestamp() - IVault(vault).epochDuration() || captureTimestamp >= Time.timestamp())
        {
            return 0;
        }
        uint256 stakeAmount = IBaseDelegator(IVault(vault).delegator()).stakeAt(
            subnetwork, operator, captureTimestamp, slashableStakeHints.stakeHints
        );
        return stakeAmount
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

    function _checkLatestSlashedCaptureTimestamp(bytes32 subnetwork, uint48 captureTimestamp) internal view {
        if (captureTimestamp < latestSlashedCaptureTimestamp[subnetwork]) {
            revert OutdatedCaptureTimestamp();
        }
    }

    function _updateCumulativeSlash(bytes32 subnetwork, address operator, uint256 amount) internal {
        _cumulativeSlash[subnetwork][operator].push(Time.timestamp(), cumulativeSlash(subnetwork, operator) + amount);
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

        __initialize(vault_, data_);
    }

    function __initialize(address vault_, bytes memory data) internal virtual {}
}
