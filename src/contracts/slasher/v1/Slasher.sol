// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ISlasher} from "src/interfaces/slasher/v1/ISlasher.sol";
import {IRegistry} from "src/interfaces/base/IRegistry.sol";
import {IVault} from "src/interfaces/vault/v1/IVault.sol";
import {IDelegator} from "src/interfaces/IDelegator.sol";
import {INetworkMiddlewareService} from "src/interfaces/INetworkMiddlewareService.sol";
import {INetworkOptInService} from "src/interfaces/INetworkOptInService.sol";
import {IOperatorOptInService} from "src/interfaces/IOperatorOptInService.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

contract Slasher is Initializable, ISlasher {
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
    address public immutable NETWORK_REGISTRY;

    /**
     * @inheritdoc ISlasher
     */
    address public immutable NETWORK_MIDDLEWARE_SERVICE;

    /**
     * @inheritdoc ISlasher
     */
    address public vault;

    /**
     * @inheritdoc ISlasher
     */
    address public delegator;

    /**
     * @inheritdoc ISlasher
     */
    SlashRequest[] public slashRequests;

    /**
     * @inheritdoc ISlasher
     */
    uint48 public vetoDuration;

    /**
     * @inheritdoc ISlasher
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
     * @inheritdoc ISlasher
     */
    function slashRequestsLength() external view returns (uint256) {
        return slashRequests.length;
    }

    /**
     * @inheritdoc ISlasher
     */
    function slashableAmountIn(
        address network,
        address resolver,
        address operator,
        uint48 duration
    ) public view returns (uint256) {
        return Math.min(
            IVault(vault).totalSupplyIn(duration),
            Math.min(
                IDelegator(delegator).networkResolverLimitIn(vault, network, resolver, duration),
                IDelegator(delegator).operatorNetworkLimitIn(vault, operator, network, duration)
            )
        );
    }

    /**
     * @inheritdoc ISlasher
     */
    function slashableAmount(address network, address resolver, address operator) public view returns (uint256) {
        return Math.min(
            IVault(vault).totalSupply(),
            Math.min(
                IDelegator(delegator).networkResolverLimit(vault, network, resolver),
                IDelegator(delegator).operatorNetworkLimit(vault, operator, network)
            )
        );
    }

    /**
     * @inheritdoc ISlasher
     */
    function minStakeDuring(
        address network,
        address resolver,
        address operator,
        uint48 duration
    ) external view returns (uint256) {
        return Math.min(
            IVault(vault).activeSupply(),
            Math.min(
                Math.min(
                    IDelegator(delegator).networkResolverLimit(vault, network, resolver),
                    IDelegator(delegator).networkResolverLimitIn(vault, network, resolver, duration)
                ),
                Math.min(
                    IDelegator(delegator).operatorNetworkLimit(vault, operator, network),
                    IDelegator(delegator).operatorNetworkLimitIn(vault, operator, network, duration)
                )
            )
        );
    }

    function initialize(address _vault, uint48 _vetoDuration, uint48 _executeDuration) external initializer {
        if (!IRegistry(VAULT_FACTORY).isEntity(_vault)) {
            revert NotVault();
        }

        vault = _vault;

        if (_vetoDuration + _executeDuration > IVault(vault).epochDuration()) {
            revert InvalidSlashDuration();
        }

        vetoDuration = _vetoDuration;
        executeDuration = _executeDuration;
    }

    /**
     * @inheritdoc ISlasher
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

        uint256 slashableAmount_ = slashableAmountIn(network, resolver, operator, vetoDuration);

        if (amount == 0 || slashableAmount_ == 0) {
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

        if (amount > slashableAmount_) {
            amount = slashableAmount_;
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
     * @inheritdoc ISlasher
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

        slashedAmount = Math.min(request.amount, slashableAmount(request.network, request.resolver, request.operator));

        if (slashedAmount != 0) {
            IVault(vault).slash(slashedAmount);
        }

        if (slashedAmount != 0) {
            IDelegator(delegator).onSlash(vault, request.network, request.resolver, request.operator, slashedAmount);
        }

        emit ExecuteSlash(slashIndex, slashedAmount);
    }

    /**
     * @inheritdoc ISlasher
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
}
