// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Entity} from "src/contracts/common/Entity.sol";

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
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract VetoSlasher is Entity, AccessControlUpgradeable, IVetoSlasher {
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
    address public immutable NETWORK_REGISTRY;

    /**
     * @inheritdoc IVetoSlasher
     */
    address public immutable NETWORK_MIDDLEWARE_SERVICE;

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

    mapping(address network => mapping(address resolver => Checkpoints.Trace256 shares)) private _resolverShares;

    constructor(
        address vaultFactory,
        address networkRegistry,
        address networkMiddlewareService,
        address networkVaultOptInService,
        address operatorVaultOptInService,
        address operatorNetworkOptInService
    ) {
        _disableInitializers();

        VAULT_FACTORY = vaultFactory;
        NETWORK_REGISTRY = networkRegistry;
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
    function requestSlash(address network, address operator, uint256 amount) external returns (uint256 slashIndex) {
        if (INetworkMiddlewareService(NETWORK_MIDDLEWARE_SERVICE).middleware(network) != msg.sender) {
            revert NotNetworkMiddleware();
        }

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
            revert SlashRequestCompleted();
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

        slashedAmount -= slashedAmount.mulDiv(request.vetoedShares, SHARES_BASE, Math.Rounding.Ceil);

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

        uint256 resolverShares_ = resolverShares(request.network, msg.sender);

        if (resolverShares_ == 0) {
            revert NotResolver();
        }

        if (request.vetoDeadline <= Time.timestamp()) {
            revert VetoPeriodEnded();
        }

        if (request.completed) {
            revert SlashRequestCompleted();
        }

        uint256 vetoedShares_ = Math.min(request.vetoedShares + resolverShares_, SHARES_BASE);

        request.vetoedShares = vetoedShares_;
        if (vetoedShares_ == SHARES_BASE) {
            request.completed = true;
        }

        emit VetoSlash(slashIndex);
    }

    function setResolverShares(address resolver, uint256 shares) external {
        if (!IRegistry(NETWORK_REGISTRY).isEntity(msg.sender)) {
            revert NotNetwork();
        }

        if (shares > SHARES_BASE) {
            revert InvalidShares();
        }

        uint48 timestamp = shares > resolverShares(msg.sender, resolver)
            ? Time.timestamp()
            : IVault(vault).currentEpochStart() + resolversSetDelay;

        Checkpoints.Trace256 storage _resolverShares_ = _resolverShares[msg.sender][resolver];
        (, uint48 latestTimestamp,) = _resolverShares_.latestCheckpoint();
        if (latestTimestamp > Time.timestamp()) {
            _resolverShares_.pop();
        }

        _resolverShares_.push(timestamp, shares);

        emit SetResolver(msg.sender, resolver, shares);
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
    }
}
