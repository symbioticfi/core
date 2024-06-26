// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {NonMigratableEntity} from "src/contracts/common/NonMigratableEntity.sol";

import {IVetoSlasher} from "src/interfaces/slasher/IVetoSlasher.sol";
import {IRegistry} from "src/interfaces/common/IRegistry.sol";
import {IVault} from "src/interfaces/vault/IVault.sol";
import {IDelegator} from "src/interfaces/delegator/IDelegator.sol";
import {INetworkMiddlewareService} from "src/interfaces/service/INetworkMiddlewareService.sol";
import {IOptInService} from "src/interfaces/service/IOptInService.sol";

import {Checkpoints} from "src/contracts/libraries/Checkpoints.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract VetoSlasher is NonMigratableEntity, AccessControlUpgradeable, IVetoSlasher {
    using Math for uint256;
    using SafeCast for uint256;
    using Checkpoints for Checkpoints.Trace256;

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

    mapping(address network => Resolvers resolvers) private _resolvers;

    mapping(address network => DelayedResolvers resolvers) private _nextResolvers;

    mapping(address network => Checkpoints.Trace256 shares) private _totalResolverShares;

    mapping(address network => mapping(address resolver => Checkpoints.Trace256 shares)) private _resolverShares;

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

    function resolversIn(address network, uint48 duration) public view returns (address[] memory) {
        return _getResolversIn(_resolvers[network], _nextResolvers[network], duration);
    }

    function resolvers(address network) public view returns (address[] memory) {
        return resolversIn(network, 0);
    }

    /**
     * @inheritdoc IVetoSlasher
     */
    function totalResolverSharesAt(address network, uint48 timestamp) public view returns (uint256) {
        return _totalResolverShares[network].upperLookupRecent(timestamp);
    }

    /**
     * @inheritdoc IVetoSlasher
     */
    function totalResolverShares(address network) public view returns (uint256) {
        return totalResolverSharesAt(network, Time.timestamp());
    }

    /**
     * @inheritdoc IVetoSlasher
     */
    function resolverSharesAt(address network, address resolver, uint48 timestamp) public view returns (uint256) {
        return _resolverShares[network][resolver].upperLookupRecent(timestamp);
    }

    /**
     * @inheritdoc IVetoSlasher
     */
    function resolverShares(address network, address resolver) public view returns (uint256) {
        return resolverSharesAt(network, resolver, Time.timestamp());
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
                completed: false,
                creation: Time.timestamp()
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

        address vault_ = vault;
        uint48 timestamp = IVault(vault_).currentEpoch() != 0
            ? IVault(vault_).previousEpochStart()
            : IVault(vault_).currentEpochStart();

        if (!IOptInService(NETWORK_VAULT_OPT_IN_SERVICE).wasOptedInAfter(request.network, vault_, timestamp)) {
            revert NetworkNotOptedInVault();
        }

        if (!IOptInService(OPERATOR_VAULT_OPT_IN_SERVICE).wasOptedInAfter(request.operator, vault_, timestamp)) {
            revert OperatorNotOptedInVault();
        }

        if (
            !IOptInService(OPERATOR_NETWORK_OPT_IN_SERVICE).wasOptedInAfter(request.operator, request.network, timestamp)
        ) {
            revert OperatorNotOptedInNetwork();
        }

        request.completed = true;

        address delegator = IVault(vault_).delegator();

        slashedAmount =
            Math.min(request.amount, IDelegator(delegator).operatorNetworkStake(request.network, request.operator));

        uint256 totalResolverShares_ = totalResolverSharesAt(request.network, request.creation);
        slashedAmount -= slashedAmount.mulDiv(request.vetoedShares, totalResolverShares_, Math.Rounding.Ceil);

        if (slashedAmount != 0) {
            IDelegator(delegator).onSlash(request.network, request.operator, slashedAmount);

            IVault(vault_).onSlash(slashedAmount);
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

        uint256 resolverShares_ = resolverSharesAt(request.network, msg.sender, request.creation);

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

    function setResolver(address network, address resolver, uint256 shares) external onlyNetworkMiddleware(network) {
        Resolvers storage currentResolvers = _resolvers[network];
        DelayedResolvers storage nextResolvers = _nextResolvers[network];

        uint256 length;
        if (nextResolvers.timestamp != 0 && nextResolvers.timestamp <= Time.timestamp()) {
            delete currentResolvers.addresses;

            length = nextResolvers.addresses.length;
            for (uint256 i; i < length; ++i) {
                currentResolvers.addresses.push(nextResolvers.addresses[i]);
            }

            delete nextResolvers.addresses;
            nextResolvers.timestamp == 0;
        }

        uint48 timestamp = _stakeIsDelegated(network) || _resolversAreSet(network)
            ? IVault(vault).currentEpochStart() + resolversSetDelay
            : Time.timestamp();

        if (nextResolvers.timestamp != 0) {
            if (nextResolvers.timestamp != timestamp) {
                length = nextResolvers.addresses.length;
                for (uint256 i; i < length; ++i) {
                    _resolverShares[network][resolver].pop();
                }
                delete nextResolvers.addresses;

                length = currentResolvers.addresses.length;
                for (uint256 i; i < length; ++i) {
                    _resolverShares[network][currentResolvers.addresses[i]].pop();
                    _resolverShares[network][currentResolvers.addresses[i]].push(timestamp, 0);
                }

                _totalResolverShares[network].pop();
                _totalResolverShares[network].push(timestamp, 0);
            }
        } else {
            length = currentResolvers.addresses.length;
            for (uint256 i; i < length; ++i) {
                _resolverShares[network][currentResolvers.addresses[i]].push(timestamp, 0);
            }

            _totalResolverShares[network].push(timestamp, 0);
        }

        _totalResolverShares[network].push(timestamp, _totalResolverShares[network].latest() + shares);
        _resolverShares[network][resolver].push(timestamp, shares);
        nextResolvers.addresses.push(resolver);
        nextResolvers.timestamp = timestamp;

        emit SetResolver(network, resolver, shares);
    }

    function _getResolversIn(
        Resolvers storage currentResolvers,
        DelayedResolvers storage nextResolvers,
        uint48 duration
    ) private view returns (address[] storage) {
        if (nextResolvers.timestamp == 0 || Time.timestamp() + duration < nextResolvers.timestamp) {
            return currentResolvers.addresses;
        }
        return nextResolvers.addresses;
    }

    function _stakeIsDelegated(address network) private view returns (bool) {
        address vault_ = vault;
        address delegator = IVault(vault_).delegator();
        uint48 epochDuration = IVault(vault_).epochDuration();
        return Math.max(
            Math.max(
                IDelegator(delegator).networkStake(network),
                IDelegator(delegator).networkStakeIn(network, epochDuration)
            ),
            IDelegator(delegator).networkStakeIn(network, 2 * epochDuration)
        ) != 0;
    }

    function _resolversAreSet(address network) private view returns (bool) {
        return _resolvers[network].addresses.length != 0 || _nextResolvers[network].timestamp != 0;
    }

    function _initialize(bytes memory data) internal override {
        (IVetoSlasher.InitParams memory params) = abi.decode(data, (IVetoSlasher.InitParams));

        if (!IRegistry(VAULT_FACTORY).isEntity(params.vault)) {
            revert NotVault();
        }

        uint48 epochDuration = IVault(params.vault).epochDuration();
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
