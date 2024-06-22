// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {NonMigratableEntity} from "src/contracts/base/NonMigratableEntity.sol";

import {ISlasher} from "src/interfaces/slashers/v1/ISlasher.sol";
import {IRegistry} from "src/interfaces/base/IRegistry.sol";
import {IVault} from "src/interfaces/vault/v1/IVault.sol";
import {IDelegator} from "src/interfaces/delegators/v1/IDelegator.sol";
import {INetworkMiddlewareService} from "src/interfaces/INetworkMiddlewareService.sol";
import {IOptInService} from "src/interfaces/IOptInService.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract Slasher is NonMigratableEntity, ISlasher {
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
        address networkMiddlewareService,
        address networkVaultOptInService,
        address operatorVaultOptInService,
        address operatorNetworkOptInService
    ) {
        _disableInitializers();

        NETWORK_MIDDLEWARE_SERVICE = networkMiddlewareService;
        NETWORK_VAULT_OPT_IN_SERVICE = networkVaultOptInService;
        OPERATOR_VAULT_OPT_IN_SERVICE = operatorVaultOptInService;
        OPERATOR_NETWORK_OPT_IN_SERVICE = operatorNetworkOptInService;
    }

    /**
     * @inheritdoc ISlasher
     */
    function slash(address network, address operator, uint256 amount) external returns (uint256) {
        if (INetworkMiddlewareService(NETWORK_MIDDLEWARE_SERVICE).middleware(network) != msg.sender) {
            revert NotNetworkMiddleware();
        }

        amount = Math.min(amount, IDelegator(IVault(vault).delegator()).operatorNetworkStake(network, operator));

        if (amount == 0) {
            revert InsufficientSlash();
        }

        if (!IOptInService(NETWORK_VAULT_OPT_IN_SERVICE).isOptedIn(network, vault)) {
            revert NetworkNotOptedInVault();
        }

        if (
            !IOptInService(OPERATOR_VAULT_OPT_IN_SERVICE).wasOptedInAfter(
                operator,
                vault,
                IVault(vault).currentEpoch() != 0
                    ? IVault(vault).previousEpochStart()
                    : IVault(vault).currentEpochStart()
            )
        ) {
            revert OperatorNotOptedInVault();
        }

        if (
            !IOptInService(OPERATOR_NETWORK_OPT_IN_SERVICE).wasOptedInAfter(
                operator,
                network,
                IVault(vault).currentEpoch() != 0
                    ? IVault(vault).previousEpochStart()
                    : IVault(vault).currentEpochStart()
            )
        ) {
            revert OperatorNotOptedInNetwork();
        }

        IVault(vault).slash(amount);

        IDelegator(IVault(vault).delegator()).onSlash(network, operator, amount);

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
