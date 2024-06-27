// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Entity} from "src/contracts/common/Entity.sol";

import {ISlasher} from "src/interfaces/slasher/ISlasher.sol";
import {IRegistry} from "src/interfaces/common/IRegistry.sol";
import {IVault} from "src/interfaces/vault/IVault.sol";
import {IDelegator} from "src/interfaces/delegator/IDelegator.sol";
import {INetworkMiddlewareService} from "src/interfaces/service/INetworkMiddlewareService.sol";
import {IOptInService} from "src/interfaces/service/IOptInService.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract Slasher is Entity, ISlasher {
    /**
     * @inheritdoc ISlasher
     */
    address public immutable VAULT_FACTORY;

    /**
     * @inheritdoc ISlasher
     */
    address public immutable NETWORK_VAULT_OPT_IN_SERVICE;

    /**
     * @inheritdoc ISlasher
     */
    address public immutable OPERATOR_VAULT_OPT_IN_SERVICE;

    /**
     * @inheritdoc ISlasher
     */
    address public immutable OPERATOR_NETWORK_OPT_IN_SERVICE;

    /**
     * @inheritdoc ISlasher
     */
    address public immutable NETWORK_MIDDLEWARE_SERVICE;

    /**
     * @inheritdoc ISlasher
     */
    address public vault;

    constructor(
        address vaultFactory,
        address networkMiddlewareService,
        address networkVaultOptInService,
        address operatorVaultOptInService,
        address operatorNetworkOptInService
    ) {
        _disableInitializers();

        VAULT_FACTORY = vaultFactory;
        NETWORK_MIDDLEWARE_SERVICE = networkMiddlewareService;
        NETWORK_VAULT_OPT_IN_SERVICE = networkVaultOptInService;
        OPERATOR_VAULT_OPT_IN_SERVICE = operatorVaultOptInService;
        OPERATOR_NETWORK_OPT_IN_SERVICE = operatorNetworkOptInService;
    }

    /**
     * @inheritdoc ISlasher
     */
    function requestSlash(address network, address operator, uint256 amount) external returns (uint256) {
        if (INetworkMiddlewareService(NETWORK_MIDDLEWARE_SERVICE).middleware(network) != msg.sender) {
            revert NotNetworkMiddleware();
        }

        address vault_ = vault;
        amount = Math.min(amount, IDelegator(IVault(vault_).delegator()).operatorNetworkStake(network, operator));

        if (amount == 0) {
            revert InsufficientSlash();
        }

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

        IDelegator(IVault(vault_).delegator()).onSlash(network, operator, amount);

        IVault(vault_).onSlash(amount);

        emit Slash(network, operator, amount);

        return amount;
    }

    function _initialize(bytes memory data) internal override {
        (ISlasher.InitParams memory params) = abi.decode(data, (ISlasher.InitParams));

        if (!IRegistry(VAULT_FACTORY).isEntity(params.vault)) {
            revert NotVault();
        }

        vault = params.vault;
    }
}
