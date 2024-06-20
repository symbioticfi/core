// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {NonMigratableEntity} from "src/contracts/base/NonMigratableEntity.sol";

import {IResolvableSlasher} from "src/interfaces/slashers/IResolvableSlasher.sol";
import {IRegistry} from "src/interfaces/base/IRegistry.sol";
import {IVault} from "src/interfaces/vault/v1/IVault.sol";
import {IDelegator} from "src/interfaces/delegators/v1/IDelegator.sol";
import {INetworkMiddlewareService} from "src/interfaces/INetworkMiddlewareService.sol";
import {INetworkOptInService} from "src/interfaces/INetworkOptInService.sol";
import {IOperatorOptInService} from "src/interfaces/IOperatorOptInService.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

contract ResolvableSlasher is NonMigratableEntity, IResolvableSlasher {
    /**
     * @inheritdoc IResolvableSlasher
     */
    address public immutable VAULT_FACTORY;

    /**
     * @inheritdoc IResolvableSlasher
     */
    address public immutable NETWORK_VAULT_OPT_IN_SERVICE;

    /**
     * @inheritdoc IResolvableSlasher
     */
    address public immutable OPERATOR_VAULT_OPT_IN_SERVICE;

    /**
     * @inheritdoc IResolvableSlasher
     */
    address public immutable OPERATOR_NETWORK_OPT_IN_SERVICE;

    /**
     * @inheritdoc IResolvableSlasher
     */
    address public immutable NETWORK_REGISTRY;

    /**
     * @inheritdoc IResolvableSlasher
     */
    address public immutable NETWORK_MIDDLEWARE_SERVICE;

    /**
     * @inheritdoc IResolvableSlasher
     */
    address public vault;

    /**
     * @inheritdoc IResolvableSlasher
     */
    SlashRequest[] public slashRequests;

    /**
     * @inheritdoc IResolvableSlasher
     */
    uint48 public vetoDuration;

    /**
     * @inheritdoc IResolvableSlasher
     */
    uint48 public executeDuration;

    constructor(
        address _vault,
        address networkRegistry,
        address networkMiddlewareService,
        address networkVaultOptInService,
        address operatorVaultOptInService,
        address operatorNetworkOptInService
    ) {
        _disableInitializers();
        if (!IRegistry(VAULT_FACTORY).isEntity(_vault)) {
            revert NotVault();
        }

        NETWORK_REGISTRY = networkRegistry;
        NETWORK_MIDDLEWARE_SERVICE = networkMiddlewareService;
        NETWORK_VAULT_OPT_IN_SERVICE = networkVaultOptInService;
        OPERATOR_VAULT_OPT_IN_SERVICE = operatorVaultOptInService;
        OPERATOR_NETWORK_OPT_IN_SERVICE = operatorNetworkOptInService;
    }

    /**
     * @inheritdoc IResolvableSlasher
     */
    function slashRequestsLength() external view returns (uint256) {
        return slashRequests.length;
    }

    /**
     * @inheritdoc IResolvableSlasher
     */
    function requestSlash(
        address network,
        address resolver,
        address operator,
        uint256 amount
    ) external returns (uint256 slashIndex) {
        if (INetworkMiddlewareService(NETWORK_MIDDLEWARE_SERVICE).middleware(network) != msg.sender) {
            revert NotNetworkMiddleware();
        }

        if (amount == 0) {
            revert InsufficientSlash();
        }

        if (!INetworkOptInService(NETWORK_VAULT_OPT_IN_SERVICE).isOptedIn(network, resolver, vault)) {
            revert NetworkNotOptedInVault();
        }

        if (
            !IOperatorOptInService(OPERATOR_VAULT_OPT_IN_SERVICE).wasOptedInAfter(
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
            !IOperatorOptInService(OPERATOR_NETWORK_OPT_IN_SERVICE).wasOptedInAfter(
                operator,
                network,
                IVault(vault).currentEpoch() != 0
                    ? IVault(vault).previousEpochStart()
                    : IVault(vault).currentEpochStart()
            )
        ) {
            revert OperatorNotOptedInNetwork();
        }

        uint48 vetoDeadline = Time.timestamp() + vetoDuration;
        uint48 executeDeadline = vetoDeadline + executeDuration;

        slashIndex = slashRequests.length;
        slashRequests.push(
            SlashRequest({
                network: network,
                resolver: resolver,
                operator: operator,
                amount: amount,
                vetoDeadline: vetoDeadline,
                executeDeadline: executeDeadline,
                completed: false
            })
        );

        emit RequestSlash(slashIndex, network, resolver, operator, amount, vetoDeadline, executeDeadline);
    }

    /**
     * @inheritdoc IResolvableSlasher
     */
    function executeSlash(uint256 slashIndex) external returns (uint256 slashedAmount) {
        if (slashIndex >= slashRequests.length) {
            revert SlashRequestNotExist();
        }

        SlashRequest storage request = slashRequests[slashIndex];

        if (request.resolver != address(0) && request.vetoDeadline > Time.timestamp()) {
            revert VetoPeriodNotEnded();
        }

        if (request.executeDeadline <= Time.timestamp()) {
            revert SlashPeriodEnded();
        }

        if (request.completed) {
            revert SlashCompleted();
        }

        request.completed = true;

        slashedAmount = Math.min(
            request.amount, IDelegator(IVault(vault).delegator()).slashableAmount(request.network, request.operator)
        );

        if (slashedAmount != 0) {
            IVault(vault).slash(slashedAmount);
        }

        if (slashedAmount != 0) {
            IDelegator(IVault(vault).delegator()).onSlash(request.network, request.operator, slashedAmount);
        }

        emit ExecuteSlash(slashIndex, slashedAmount);
    }

    /**
     * @inheritdoc IResolvableSlasher
     */
    function vetoSlash(uint256 slashIndex) external {
        if (slashIndex >= slashRequests.length) {
            revert SlashRequestNotExist();
        }

        SlashRequest storage request = slashRequests[slashIndex];

        if (request.resolver != msg.sender) {
            revert NotResolver();
        }

        if (request.vetoDeadline <= Time.timestamp()) {
            revert VetoPeriodEnded();
        }

        if (request.completed) {
            revert SlashCompleted();
        }

        request.completed = true;

        emit VetoSlash(slashIndex);
    }

    function _initialize(bytes memory data) internal override {
        (IResolvableSlasher.InitParams memory params) = abi.decode(data, (IResolvableSlasher.InitParams));

        if (!IRegistry(VAULT_FACTORY).isEntity(params.vault)) {
            revert NotVault();
        }

        vault = params.vault;

        if (params.vetoDuration + params.executeDuration > IVault(vault).epochDuration()) {
            revert InvalidSlashDuration();
        }

        vetoDuration = params.vetoDuration;
        executeDuration = params.executeDuration;
    }
}
