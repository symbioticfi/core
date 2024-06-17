// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IStakingController} from "src/interfaces/stakingController/v1/IStakingController.sol";
import {IRegistry} from "src/interfaces/base/IRegistry.sol";
import {IVault} from "src/interfaces/vault/v1/IVault.sol";
import {ILimiter} from "src/interfaces/ILimiter.sol";
import {INetworkMiddlewareService} from "src/interfaces/INetworkMiddlewareService.sol";
import {INetworkOptInService} from "src/interfaces/INetworkOptInService.sol";
import {IOperatorOptInService} from "src/interfaces/IOperatorOptInService.sol";
import {ICollateral} from "src/interfaces/base/ICollateral.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

contract StakingController is Initializable, IStakingController {
    /**
     * @inheritdoc IStakingController
     */
    address public immutable VAULT_FACTORY;

    /**
     * @dev Some dead address to issue debt to.
     */
    address internal constant DEAD = address(0xdEaD);

    /**
     * @inheritdoc IStakingController
     */
    address public immutable NETWORK_VAULT_OPT_IN_SERVICE;

    /**
     * @inheritdoc IStakingController
     */
    address public immutable OPERATOR_VAULT_OPT_IN_SERVICE;

    /**
     * @inheritdoc IStakingController
     */
    address public immutable OPERATOR_NETWORK_OPT_IN_SERVICE;

    /**
     * @inheritdoc IStakingController
     */
    address public immutable NETWORK_REGISTRY;

    /**
     * @inheritdoc IStakingController
     */
    address public immutable NETWORK_MIDDLEWARE_SERVICE;

    /**
     * @inheritdoc IStakingController
     */
    address public vault;

    /**
     * @inheritdoc IStakingController
     */
    address public limiter;

    /**
     * @inheritdoc IStakingController
     */
    SlashRequest[] public slashRequests;

    /**
     * @inheritdoc IStakingController
     */
    uint48 public vetoDuration;

    /**
     * @inheritdoc IStakingController
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
     * @inheritdoc IStakingController
     */
    function slashRequestsLength() external view returns (uint256) {
        return slashRequests.length;
    }

    /**
     * @inheritdoc IStakingController
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
                ILimiter(limiter).networkResolverLimitIn(vault, network, resolver, duration),
                ILimiter(limiter).operatorNetworkLimitIn(vault, operator, network, duration)
            )
        );
    }

    /**
     * @inheritdoc IStakingController
     */
    function slashableAmount(address network, address resolver, address operator) public view returns (uint256) {
        return Math.min(
            IVault(vault).totalSupply(),
            Math.min(
                ILimiter(limiter).networkResolverLimit(vault, network, resolver),
                ILimiter(limiter).operatorNetworkLimit(vault, operator, network)
            )
        );
    }

    /**
     * @inheritdoc IStakingController
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
                    ILimiter(limiter).networkResolverLimit(vault, network, resolver),
                    ILimiter(limiter).networkResolverLimitIn(vault, network, resolver, duration)
                ),
                Math.min(
                    ILimiter(limiter).operatorNetworkLimit(vault, operator, network),
                    ILimiter(limiter).operatorNetworkLimitIn(vault, operator, network, duration)
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
     * @inheritdoc IStakingController
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
     * @inheritdoc IStakingController
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

        slashedAmount = IVault(vault).onSlash(slashedAmount);

        emit ExecuteSlash(slashIndex, slashedAmount);

        if (slashedAmount == 0) {
            return 0;
        }

        ILimiter(limiter).onSlash(vault, request.network, request.resolver, request.operator, slashedAmount);

        ICollateral(IVault(vault).collateral()).issueDebt(DEAD, slashedAmount);
    }

    /**
     * @inheritdoc IStakingController
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
