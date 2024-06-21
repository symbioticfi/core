// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {NonMigratableEntity} from "src/contracts/base/NonMigratableEntity.sol";

import {IResolvableSlasher} from "src/interfaces/slashers/v1/IResolvableSlasher.sol";
import {IRegistry} from "src/interfaces/base/IRegistry.sol";
import {IVault} from "src/interfaces/vault/v1/IVault.sol";
import {IDelegator} from "src/interfaces/delegators/v1/IDelegator.sol";
import {INetworkMiddlewareService} from "src/interfaces/INetworkMiddlewareService.sol";
import {INetworkOptInService} from "src/interfaces/INetworkOptInService.sol";
import {IOperatorOptInService} from "src/interfaces/IOperatorOptInService.sol";

import {Checkpoints} from "src/contracts/libraries/Checkpoints.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract ResolvableSlasher is NonMigratableEntity, AccessControlUpgradeable, IResolvableSlasher {
    using Checkpoints for Checkpoints.Trace256;
    using Math for uint256;

    /**
     * @inheritdoc IResolvableSlasher
     */
    uint256 public MAX_SHARES = 10 ** 36;

    /**
     * @inheritdoc IResolvableSlasher
     */
    uint256 public BASE_SHARES = 10 ** 36;

    /**
     * @inheritdoc IResolvableSlasher
     */
    bytes32 public constant RESOLVER_SHARES_SET_ROLE = keccak256("RESOLVER_SHARES_SET_ROLE");

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

    mapping(address network => Checkpoints.Trace256 checkpoint) private _totalResolverShares;

    mapping(address network => mapping(address resolver => Checkpoints.Trace256 checkpoint)) private _resolverShares;

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
     * @inheritdoc IResolvableSlasher
     */
    function slashRequestsLength() external view returns (uint256) {
        return slashRequests.length;
    }

    /**
     * @inheritdoc IResolvableSlasher
     */
    function totalResolverSharesAt(address network, uint48 timestamp) public view returns (uint256) {
        return _totalResolverShares[network].upperLookupRecent(timestamp);
    }

    /**
     * @inheritdoc IResolvableSlasher
     */
    function totalResolverShares(address network) public view returns (uint256) {
        return _totalResolverShares[network].upperLookupRecent(Time.timestamp());
    }

    /**
     * @inheritdoc IResolvableSlasher
     */
    function resolverSharesAt(address network, address resolver, uint48 timestamp) public view returns (uint256) {
        return _resolverShares[network][resolver].upperLookupRecent(timestamp);
    }

    /**
     * @inheritdoc IResolvableSlasher
     */
    function resolverShares(address network, address resolver) public view returns (uint256) {
        return _resolverShares[network][resolver].upperLookupRecent(Time.timestamp());
    }

    /**
     * @inheritdoc IResolvableSlasher
     */
    function resolverNetworkStakeIn(
        address network,
        address resolver,
        uint48 duration
    ) external view returns (uint256) {
        return IDelegator(IVault(vault).delegator()).networkStakeIn(network, duration).mulDiv(
            resolverSharesAt(network, resolver, Time.timestamp() + duration),
            totalResolverSharesAt(network, Time.timestamp() + duration)
        );
    }

    /**
     * @inheritdoc IResolvableSlasher
     */
    function resolverNetworkStake(address network, address resolver) public view returns (uint256) {
        return IDelegator(IVault(vault).delegator()).networkStake(network).mulDiv(
            resolverShares(network, resolver), totalResolverShares(network)
        );
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

        address delegator = IVault(vault).delegator();
        uint256 resolverSlashableAmount = resolverNetworkStake(request.network, request.resolver);

        slashedAmount = Math.min(
            Math.min(request.amount, IDelegator(delegator).operatorNetworkStake(request.network, request.operator)),
            resolverSlashableAmount
        );

        uint256 resolverShares_ = resolverShares(request.network, request.resolver);
        uint256 resolverSlashedShares =
            slashedAmount.mulDiv(resolverShares_, resolverSlashableAmount, Math.Rounding.Ceil);

        _insertSharesCheckpointAtNow(
            _totalResolverShares[request.network], totalResolverShares(request.network) - resolverSlashedShares
        );

        _insertSharesCheckpointAtNow(
            _resolverShares[request.network][request.resolver], resolverShares_ - resolverSlashedShares
        );

        if (slashedAmount != 0) {
            IVault(vault).slash(slashedAmount);

            IDelegator(delegator).onSlash(request.network, request.operator, slashedAmount);
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

    function setResolverShares(
        address network,
        address resolver,
        uint256 shares
    ) external onlyRole(RESOLVER_SHARES_SET_ROLE) {
        if (shares > MAX_SHARES) {
            revert InvalidShares();
        }

        shares *= BASE_SHARES;

        uint48 timestamp = IVault(vault).currentEpochStart() + 2 * IVault(vault).epochDuration();

        _totalResolverShares[network].push(
            timestamp, _totalResolverShares[network].latest() + shares - _resolverShares[network][resolver].latest()
        );

        _resolverShares[network][resolver].push(timestamp, shares);

        emit SetResolverShares(network, resolver, shares);
    }

    function _insertSharesCheckpointAtNow(Checkpoints.Trace256 storage checkpoints, uint256 value) private {
        (, uint48 latestTimestamp1, uint256 latestValue1) = checkpoints.latestCheckpoint();
        if (Time.timestamp() < latestTimestamp1) {
            checkpoints.pop();
            (, uint48 latestTimestamp2, uint256 latestValue2) = checkpoints.latestCheckpoint();
            if (Time.timestamp() < latestTimestamp2) {
                checkpoints.pop();
                checkpoints.push(Time.timestamp(), value);
                checkpoints.push(latestTimestamp2, latestValue2);
            } else {
                checkpoints.push(Time.timestamp(), value);
            }
            checkpoints.push(latestTimestamp1, latestValue1);
        } else {
            checkpoints.push(Time.timestamp(), value);
        }
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

        _grantRole(RESOLVER_SHARES_SET_ROLE, Ownable(params.vault).owner());
    }
}
