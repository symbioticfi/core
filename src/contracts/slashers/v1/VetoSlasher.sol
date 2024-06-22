// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {NonMigratableEntity} from "src/contracts/base/NonMigratableEntity.sol";

import {IVetoSlasher} from "src/interfaces/slashers/v1/IVetoSlasher.sol";
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
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract VetoSlasher is NonMigratableEntity, AccessControlUpgradeable, IVetoSlasher {
    using Checkpoints for Checkpoints.Trace256;
    using Math for uint256;
    using SafeCast for uint256;

    /**
     * @inheritdoc IVetoSlasher
     */
    uint256 public SHARES_BASE = 10 ** 18;

    /**
     * @inheritdoc IVetoSlasher
     */
    bytes32 public constant RESOLVER_SHARES_SET_ROLE = keccak256("RESOLVER_SHARES_SET_ROLE");

    /**
     * @inheritdoc IVetoSlasher
     */
    address public immutable VAULT_FACTORY;

    /**
     * @inheritdoc IVetoSlasher
     */
    address public immutable NETWORK_VAULT_OPT_IN_SERVICE;

    /**
     * @inheritdoc IVetoSlasher
     */
    address public immutable OPERATOR_VAULT_OPT_IN_SERVICE;

    /**
     * @inheritdoc IVetoSlasher
     */
    address public immutable OPERATOR_NETWORK_OPT_IN_SERVICE;

    /**
     * @inheritdoc IVetoSlasher
     */
    address public immutable NETWORK_MIDDLEWARE_SERVICE;

    /**
     * @inheritdoc IVetoSlasher
     */
    address public vault;

    /**
     * @inheritdoc IVetoSlasher
     */
    SlashRequest[] public slashRequests;

    /**
     * @inheritdoc IVetoSlasher
     */
    uint48 public vetoDuration;

    /**
     * @inheritdoc IVetoSlasher
     */
    uint48 public executeDuration;

    /**
     * @inheritdoc IVetoSlasher
     */
    uint48 public resolversSetDelay;

    /**
     * @inheritdoc IVetoSlasher
     */
    mapping(address network => mapping(address resolver => DelayedShares shares)) public nextResolverShares;

    mapping(address network => mapping(address resolver => Shares shares)) private _resolverShares;

    modifier onlyNetworkMiddleware(address network) {
        if (INetworkMiddlewareService(NETWORK_MIDDLEWARE_SERVICE).middleware(network) != msg.sender) {
            revert NotNetworkMiddleware();
        }
        _;
    }

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
     * @inheritdoc IVetoSlasher
     */
    function slashRequestsLength() external view returns (uint256) {
        return slashRequests.length;
    }

    /**
     * @inheritdoc IVetoSlasher
     */
    function resolverSharesIn(address network, address resolver, uint48 duration) public view returns (uint256) {
        return _getSharesAt(
            _resolverShares[network][resolver], nextResolverShares[network][resolver], Time.timestamp() + duration
        );
    }

    /**
     * @inheritdoc IVetoSlasher
     */
    function resolverShares(address network, address resolver) public view returns (uint256) {
        return _getSharesAt(_resolverShares[network][resolver], nextResolverShares[network][resolver], Time.timestamp());
    }

    /**
     * @inheritdoc IVetoSlasher
     */
    function requestSlash(
        address network,
        address operator,
        uint256 amount
    ) external onlyNetworkMiddleware(network) returns (uint256 slashIndex) {
        if (amount == 0) {
            revert InsufficientSlash();
        }

        if (!INetworkOptInService(NETWORK_VAULT_OPT_IN_SERVICE).isOptedIn(network, address(0), vault)) {
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
                operator: operator,
                amount: amount,
                vetoDeadline: vetoDeadline,
                executeDeadline: executeDeadline,
                vetoedShares: 0,
                completed: false
            })
        );

        emit RequestSlash(slashIndex, network, operator, amount, vetoDeadline, executeDeadline);
    }

    /**
     * @inheritdoc IVetoSlasher
     */
    function executeSlash(uint256 slashIndex) external returns (uint256 slashedAmount) {
        if (slashIndex >= slashRequests.length) {
            revert SlashRequestNotExist();
        }

        SlashRequest storage request = slashRequests[slashIndex];

        if (request.vetoDeadline > Time.timestamp()) {
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

        slashedAmount =
            Math.min(request.amount, IDelegator(delegator).operatorNetworkStake(request.network, request.operator));

        slashedAmount -= slashedAmount.mulDiv(request.vetoedShares, SHARES_BASE, Math.Rounding.Ceil);

        if (slashedAmount != 0) {
            IVault(vault).slash(slashedAmount);

            IDelegator(delegator).onSlash(request.network, request.operator, slashedAmount);
        }

        emit ExecuteSlash(slashIndex, slashedAmount);
    }

    /**
     * @inheritdoc IVetoSlasher
     */
    function vetoSlash(uint256 slashIndex) external {
        if (slashIndex >= slashRequests.length) {
            revert SlashRequestNotExist();
        }

        SlashRequest storage request = slashRequests[slashIndex];

        uint256 resolverShares_ = resolverShares(request.network, msg.sender);

        if (resolverShares_ == 0) {
            revert NotResolver();
        }

        if (request.vetoDeadline <= Time.timestamp()) {
            revert VetoPeriodEnded();
        }

        if (request.completed) {
            revert SlashCompleted();
        }

        uint256 vetoedShares_ = request.vetoedShares + resolverShares_;

        request.vetoedShares = vetoedShares_;
        if (vetoedShares_ == SHARES_BASE) {
            request.completed = true;
        }

        emit VetoSlash(slashIndex);
    }

    function setResolvers(
        address network,
        address[] calldata resolvers,
        uint256[] calldata shares
    ) external onlyNetworkMiddleware(network) {
        uint256 length = resolvers.length;
        if (length != shares.length) {
            revert InvalidResolversLength();
        }

        uint256 totalShares;
        for (uint256 i; i < length; ++i) {
            totalShares += shares[i];

            _setShares(
                _resolverShares[network][resolvers[i]],
                nextResolverShares[network][resolvers[i]],
                shares[i],
                _stakeIsDelegated(network) ? resolversSetDelay : 0
            );
        }

        if (totalShares != SHARES_BASE) {
            revert InvalidTotalShares();
        }

        emit SetResolvers(network, resolvers, shares);
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

    function _getSharesAt(
        Shares storage shares,
        DelayedShares storage nextShares,
        uint48 timestamp
    ) private view returns (uint256) {
        if (nextShares.timestamp == 0 || timestamp < nextShares.timestamp) {
            return shares.amount;
        }
        return nextShares.amount;
    }

    function _setShares(
        Shares storage shares,
        DelayedShares storage nextShares,
        uint256 amount,
        uint48 delay
    ) private {
        _updateShares(shares, nextShares);

        nextShares.amount = amount;
        nextShares.timestamp = IVault(vault).currentEpochStart() + delay;
    }

    function _updateShares(Shares storage shares, DelayedShares storage nextShares) internal {
        if (nextShares.timestamp != 0 && nextShares.timestamp <= Time.timestamp()) {
            shares.amount = nextShares.amount;
            nextShares.timestamp = 0;
            nextShares.amount = 0;
        }
    }

    function _stakeIsDelegated(address network) private view returns (bool) {
        address delegator = IVault(vault).delegator();
        uint48 epochDuration = IVault(vault).epochDuration();
        return Math.max(
            Math.max(
                IDelegator(delegator).maxNetworkStake(network),
                IDelegator(delegator).maxNetworkStakeIn(network, epochDuration)
            ),
            IDelegator(delegator).maxNetworkStakeIn(network, 2 * epochDuration)
        ) != 0;
    }

    function _initialize(bytes memory data) internal override {
        (IVetoSlasher.InitParams memory params) = abi.decode(data, (IVetoSlasher.InitParams));

        if (!IRegistry(VAULT_FACTORY).isEntity(params.vault)) {
            revert NotVault();
        }

        uint48 epochDuration = IVault(vault).epochDuration();
        if (params.vetoDuration + params.executeDuration > epochDuration) {
            revert InvalidSlashDuration();
        }

        if (params.resolversSetEpochsDelay < 3) {
            revert InvalidResolversSetEpochsDelay();
        }

        vault = params.vault;

        vetoDuration = params.vetoDuration;
        executeDuration = params.executeDuration;

        resolversSetDelay = (params.resolversSetEpochsDelay * epochDuration).toUint48();

        _grantRole(RESOLVER_SHARES_SET_ROLE, Ownable(params.vault).owner());
    }
}
