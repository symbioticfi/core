// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {Entity} from "src/contracts/common/Entity.sol";

import {IBaseSlasher} from "src/interfaces/slasher/IBaseSlasher.sol";
import {INetworkMiddlewareService} from "src/interfaces/service/INetworkMiddlewareService.sol";
import {IRegistry} from "src/interfaces/common/IRegistry.sol";
import {IOptInService} from "src/interfaces/service/IOptInService.sol";
import {IVault} from "src/interfaces/vault/IVault.sol";
import {IBaseDelegator} from "src/interfaces/delegator/IBaseDelegator.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

abstract contract BaseSlasher is Entity, IBaseSlasher {
    /**
     * @inheritdoc IBaseSlasher
     */
    address public immutable VAULT_FACTORY;

    /**
     * @inheritdoc IBaseSlasher
     */
    address public immutable NETWORK_VAULT_OPT_IN_SERVICE;

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

    modifier onlyNetworkMiddleware(address network) {
        if (INetworkMiddlewareService(NETWORK_MIDDLEWARE_SERVICE).middleware(network) != msg.sender) {
            revert NotNetworkMiddleware();
        }

        _;
    }

    constructor(
        address vaultFactory,
        address networkMiddlewareService,
        address networkVaultOptInService,
        address operatorVaultOptInService,
        address operatorNetworkOptInService,
        address slasherFactory
    ) Entity(slasherFactory) {
        VAULT_FACTORY = vaultFactory;
        NETWORK_MIDDLEWARE_SERVICE = networkMiddlewareService;
        NETWORK_VAULT_OPT_IN_SERVICE = networkVaultOptInService;
        OPERATOR_VAULT_OPT_IN_SERVICE = operatorVaultOptInService;
        OPERATOR_NETWORK_OPT_IN_SERVICE = operatorNetworkOptInService;
    }

    function _checkOptIns(address network, address operator) internal view {
        address vault_ = vault;
        uint48 timestamp = IVault(vault_).currentEpoch() != 0
            ? IVault(vault_).previousEpochStart()
            : IVault(vault_).currentEpochStart();

        if (!IOptInService(NETWORK_VAULT_OPT_IN_SERVICE).wasOptedInAfter(network, vault_, timestamp)) {
            revert NetworkNotOptedInVault();
        }

        if (!IOptInService(OPERATOR_VAULT_OPT_IN_SERVICE).wasOptedInAfter(operator, vault_, timestamp)) {
            revert OperatorNotOptedInVault();
        }

        if (!IOptInService(OPERATOR_NETWORK_OPT_IN_SERVICE).wasOptedInAfter(operator, network, timestamp)) {
            revert OperatorNotOptedInNetwork();
        }
    }

    function _callOnSlash(address network, address operator, uint256 amount) internal virtual {
        address vault_ = vault;

        IBaseDelegator(IVault(vault_).delegator()).onSlash(network, operator, amount);

        IVault(vault_).onSlash(amount);
    }

    function _initializeInternal(address vault_, bytes memory data) internal virtual {}

    function _initialize(bytes memory data) internal override {
        (address vault_, bytes memory data_) = abi.decode(data, (address, bytes));

        if (!IRegistry(VAULT_FACTORY).isEntity(vault_)) {
            revert NotVault();
        }

        vault = vault_;

        _initializeInternal(vault_, data_);
    }
}
