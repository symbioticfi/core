// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {BaseSlasher} from "./BaseSlasher.sol";

import {IVetoSlasher} from "src/interfaces/slasher/IVetoSlasher.sol";
import {IRegistry} from "src/interfaces/common/IRegistry.sol";
import {IVault} from "src/interfaces/vault/IVault.sol";
import {IDelegator} from "src/interfaces/delegator/IDelegator.sol";

import {Checkpoints} from "src/contracts/libraries/Checkpoints.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract VetoSlasher is BaseSlasher, AccessControlUpgradeable, IVetoSlasher {
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
    address public immutable NETWORK_REGISTRY;

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
        address networkMiddlewareService,
        address networkVaultOptInService,
        address operatorVaultOptInService,
        address operatorNetworkOptInService,
        address networkRegistry
    )
        BaseSlasher(
            vaultFactory,
            networkMiddlewareService,
            networkVaultOptInService,
            operatorVaultOptInService,
            operatorNetworkOptInService
        )
    {
        NETWORK_REGISTRY = networkRegistry;
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
            revert SlashRequestCompleted();
        }

        _checkOptIns(request.network, request.operator);

        request.completed = true;

        slashedAmount = Math.min(
            request.amount,
            IDelegator(IVault(vault).delegator()).operatorNetworkStake(request.network, request.operator)
        );

        slashedAmount -= slashedAmount.mulDiv(request.vetoedShares, SHARES_BASE, Math.Rounding.Ceil);

        if (slashedAmount != 0) {
            _callOnSlash(request.network, request.operator, slashedAmount);
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

    function _initializeSlasher(bytes memory data) internal override returns (address) {
        (IVetoSlasher.InitParams memory params) = abi.decode(data, (IVetoSlasher.InitParams));

        uint48 epochDuration = IVault(params.vault).epochDuration();
        if (params.vetoDuration + params.executeDuration > epochDuration) {
            revert InvalidSlashDuration();
        }

        if (params.resolversSetEpochsDelay < 3) {
            revert InvalidResolversSetEpochsDelay();
        }

        vetoDuration = params.vetoDuration;
        executeDuration = params.executeDuration;

        resolversSetDelay = (params.resolversSetEpochsDelay * epochDuration).toUint48();

        return params.vault;
    }
}
