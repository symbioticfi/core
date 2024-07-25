// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Entity} from "src/contracts/common/Entity.sol";
import {StaticDelegateCallable} from "src/contracts/common/StaticDelegateCallable.sol";

import {IBaseSlasher} from "src/interfaces/slasher/IBaseSlasher.sol";
import {INetworkMiddlewareService} from "src/interfaces/service/INetworkMiddlewareService.sol";
import {IRegistry} from "src/interfaces/common/IRegistry.sol";
import {IOptInService} from "src/interfaces/service/IOptInService.sol";
import {IVault} from "src/interfaces/vault/IVault.sol";
import {IBaseDelegator} from "src/interfaces/delegator/IBaseDelegator.sol";

import {Checkpoints} from "src/contracts/libraries/Checkpoints.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

abstract contract BaseSlasher is Entity, StaticDelegateCallable, IBaseSlasher {
    using Checkpoints for Checkpoints.Trace256;

    /**
     * @inheritdoc IBaseSlasher
     */
    address public immutable VAULT_FACTORY;

    /**
     * @inheritdoc IBaseSlasher
     */
    address public immutable OPERATOR_VAULT_OPT_IN_SERVICE;

    /**
     * @inheritdoc IBaseSlasher
     */
    address public immutable OPERATOR_NETWORK_OPT_IN_SERVICE;

    /**
     * @inheritdoc IBaseSlasher
     */
    address public immutable NETWORK_MIDDLEWARE_SERVICE;

    /**
     * @inheritdoc IBaseSlasher
     */
    address public vault;

    mapping(address network => mapping(address operator => Checkpoints.Trace256 amount)) internal _cumulativeSlash;

    modifier onlyNetworkMiddleware(address network) {
        if (INetworkMiddlewareService(NETWORK_MIDDLEWARE_SERVICE).middleware(network) != msg.sender) {
            revert NotNetworkMiddleware();
        }

        _;
    }

    constructor(
        address vaultFactory,
        address networkMiddlewareService,
        address operatorVaultOptInService,
        address operatorNetworkOptInService,
        address slasherFactory,
        uint64 entityType
    ) Entity(slasherFactory, entityType) {
        VAULT_FACTORY = vaultFactory;
        NETWORK_MIDDLEWARE_SERVICE = networkMiddlewareService;
        OPERATOR_VAULT_OPT_IN_SERVICE = operatorVaultOptInService;
        OPERATOR_NETWORK_OPT_IN_SERVICE = operatorNetworkOptInService;
    }

    /**
     * @inheritdoc IBaseSlasher
     */
    function cumulativeSlashAt(
        address network,
        address operator,
        uint48 timestamp,
        bytes memory hint
    ) public view returns (uint256) {
        return _cumulativeSlash[network][operator].upperLookupRecent(timestamp, hint);
    }

    /**
     * @inheritdoc IBaseSlasher
     */
    function cumulativeSlash(address network, address operator) public view returns (uint256) {
        return _cumulativeSlash[network][operator].latest();
    }

    /**
     * @inheritdoc IBaseSlasher
     */
    function slashableStake(
        address network,
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
            network, operator, captureTimestamp, slashableStakeHints.stakeHints
        );
        return stakeAmount
            - Math.min(
                cumulativeSlash(network, operator)
                    - cumulativeSlashAt(network, operator, captureTimestamp, slashableStakeHints.cumulativeSlashFromHint),
                stakeAmount
            );
    }

    function _checkOptIns(
        address network,
        address operator,
        uint48 captureTimestamp,
        bytes memory hints
    ) internal view {
        OptInHints memory optInHints;
        if (hints.length > 0) {
            optInHints = abi.decode(hints, (OptInHints));
        }

        if (
            !IOptInService(OPERATOR_VAULT_OPT_IN_SERVICE).isOptedInAt(
                operator, vault, captureTimestamp, optInHints.operatorVaultOptInHint
            )
        ) {
            revert OperatorNotOptedInVault();
        }

        if (
            !IOptInService(OPERATOR_NETWORK_OPT_IN_SERVICE).isOptedInAt(
                operator, network, captureTimestamp, optInHints.operatorNetworkOptInHint
            )
        ) {
            revert OperatorNotOptedInNetwork();
        }
    }

    function _updateCumulativeSlash(address network, address operator, uint256 amount) internal {
        _cumulativeSlash[network][operator].push(Time.timestamp(), cumulativeSlash(network, operator) + amount);
    }

    function _callOnSlash(
        address network,
        address operator,
        uint256 amount,
        uint48 captureTimestamp,
        bytes memory hints
    ) internal virtual {
        OnSlashHints memory onSlashHints;
        if (hints.length > 0) {
            onSlashHints = abi.decode(hints, (OnSlashHints));
        }

        address vault_ = vault;

        IBaseDelegator(IVault(vault_).delegator()).onSlash(
            network, operator, amount, captureTimestamp, onSlashHints.delegatorOnSlashHints
        );

        IVault(vault_).onSlash(amount, captureTimestamp);
    }

    function _initializeInternal(address vault_, bytes memory data) internal virtual {}

    function _initialize(bytes calldata data) internal override {
        (address vault_, bytes memory data_) = abi.decode(data, (address, bytes));

        if (!IRegistry(VAULT_FACTORY).isEntity(vault_)) {
            revert NotVault();
        }

        vault = vault_;

        _initializeInternal(vault_, data_);
    }
}
