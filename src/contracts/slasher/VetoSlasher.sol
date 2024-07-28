// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {BaseSlasher} from "./BaseSlasher.sol";

import {IVetoSlasher} from "src/interfaces/slasher/IVetoSlasher.sol";
import {IRegistry} from "src/interfaces/common/IRegistry.sol";
import {IVault} from "src/interfaces/vault/IVault.sol";

import {Checkpoints} from "src/contracts/libraries/Checkpoints.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract VetoSlasher is BaseSlasher, IVetoSlasher {
    using Math for uint256;
    using SafeCast for uint256;
    using Checkpoints for Checkpoints.Trace256;

    /**
     * @inheritdoc IVetoSlasher
     */
    uint256 public constant SHARES_BASE = 10 ** 18;

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
    uint256 public resolverSetEpochsDelay;

    /**
     * @inheritdoc IVetoSlasher
     */
    mapping(address resolver => mapping(uint256 slashIndex => bool value)) public hasVetoed;

    mapping(address network => mapping(address resolver => Checkpoints.Trace256 shares)) internal _resolverShares;

    constructor(
        address vaultFactory,
        address networkMiddlewareService,
        address networkRegistry,
        address slasherFactory,
        uint64 entityType
    ) BaseSlasher(vaultFactory, networkMiddlewareService, slasherFactory, entityType) {
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
    function resolverSharesAt(
        address network,
        address resolver,
        uint48 timestamp,
        bytes memory hint
    ) public view returns (uint256) {
        return _resolverShares[network][resolver].upperLookupRecent(timestamp, hint);
    }

    /**
     * @inheritdoc IVetoSlasher
     */
    function resolverShares(address network, address resolver, bytes memory hint) public view returns (uint256) {
        return resolverSharesAt(network, resolver, Time.timestamp(), hint);
    }

    /**
     * @inheritdoc IVetoSlasher
     */
    function requestSlash(
        address network,
        address operator,
        uint256 amount,
        uint48 captureTimestamp,
        bytes calldata hints
    ) external onlyNetworkMiddleware(network) returns (uint256 slashIndex) {
        RequestSlashHints memory requestSlashHints;
        if (hints.length > 0) {
            requestSlashHints = abi.decode(hints, (RequestSlashHints));
        }

        if (
            captureTimestamp < Time.timestamp() + vetoDuration - IVault(vault).epochDuration()
                || captureTimestamp >= Time.timestamp()
        ) {
            revert InvalidCaptureTimestamp();
        }

        _checkLatestSlashedCaptureTimestamp(network, captureTimestamp);

        amount =
            Math.min(amount, slashableStake(network, operator, captureTimestamp, requestSlashHints.slashableStakeHints));
        if (amount == 0) {
            revert InsufficientSlash();
        }

        uint48 vetoDeadline = Time.timestamp() + vetoDuration;

        slashIndex = slashRequests.length;
        slashRequests.push(
            SlashRequest({
                network: network,
                operator: operator,
                amount: amount,
                captureTimestamp: captureTimestamp,
                vetoDeadline: vetoDeadline,
                vetoedShares: 0,
                completed: false
            })
        );

        emit RequestSlash(slashIndex, network, operator, amount, captureTimestamp, vetoDeadline);
    }

    /**
     * @inheritdoc IVetoSlasher
     */
    function executeSlash(uint256 slashIndex, bytes calldata hints) external returns (uint256 slashedAmount) {
        ExecuteSlashHints memory executeSlashHints;
        if (hints.length > 0) {
            executeSlashHints = abi.decode(hints, (ExecuteSlashHints));
        }

        if (slashIndex >= slashRequests.length) {
            revert SlashRequestNotExist();
        }

        SlashRequest storage request = slashRequests[slashIndex];

        if (request.vetoDeadline > Time.timestamp()) {
            revert VetoPeriodNotEnded();
        }

        if (Time.timestamp() - request.captureTimestamp > IVault(vault).epochDuration()) {
            revert SlashPeriodEnded();
        }

        _checkLatestSlashedCaptureTimestamp(request.network, request.captureTimestamp);

        if (request.completed) {
            revert SlashRequestCompleted();
        }

        request.completed = true;

        if (latestSlashedCaptureTimestamp[request.network] < request.captureTimestamp) {
            latestSlashedCaptureTimestamp[request.network] = request.captureTimestamp;
        }

        slashedAmount = Math.min(
            request.amount,
            slashableStake(
                request.network, request.operator, request.captureTimestamp, executeSlashHints.slashableStakeHints
            )
        );

        slashedAmount -= slashedAmount.mulDiv(request.vetoedShares, SHARES_BASE, Math.Rounding.Ceil);

        if (slashedAmount > 0) {
            _updateCumulativeSlash(request.network, request.operator, slashedAmount);
        }

        _callOnSlash(request.network, request.operator, slashedAmount, request.captureTimestamp);

        emit ExecuteSlash(slashIndex, slashedAmount);
    }

    /**
     * @inheritdoc IVetoSlasher
     */
    function vetoSlash(uint256 slashIndex, bytes calldata hints) external {
        VetoSlashHints memory vetoSlashHints;
        if (hints.length > 0) {
            vetoSlashHints = abi.decode(hints, (VetoSlashHints));
        }

        if (slashIndex >= slashRequests.length) {
            revert SlashRequestNotExist();
        }

        SlashRequest storage request = slashRequests[slashIndex];

        uint256 resolverShares_ =
            resolverSharesAt(request.network, msg.sender, request.captureTimestamp, vetoSlashHints.resolverSharesHint);

        if (resolverShares_ == 0) {
            revert NotResolver();
        }

        if (request.vetoDeadline <= Time.timestamp()) {
            revert VetoPeriodEnded();
        }

        if (request.completed) {
            revert SlashRequestCompleted();
        }

        if (hasVetoed[msg.sender][slashIndex]) {
            revert AlreadyVetoed();
        }

        hasVetoed[msg.sender][slashIndex] = true;

        uint256 vetoedShares_ = Math.min(request.vetoedShares + resolverShares_, SHARES_BASE);

        request.vetoedShares = vetoedShares_;
        if (vetoedShares_ == SHARES_BASE) {
            request.completed = true;
        }

        emit VetoSlash(slashIndex, msg.sender, resolverShares_);
    }

    function setResolverShares(address resolver, uint256 shares, bytes calldata hints) external {
        SetResolverSharesHints memory setResolverSharesHints;
        if (hints.length > 0) {
            setResolverSharesHints = abi.decode(hints, (SetResolverSharesHints));
        }

        if (!IRegistry(NETWORK_REGISTRY).isEntity(msg.sender)) {
            revert NotNetwork();
        }

        if (shares > SHARES_BASE) {
            revert InvalidShares();
        }

        uint48 timestamp = shares > resolverShares(msg.sender, resolver, setResolverSharesHints.resolverSharesHint)
            ? Time.timestamp()
            : (IVault(vault).currentEpochStart() + resolverSetEpochsDelay * IVault(vault).epochDuration()).toUint48();

        Checkpoints.Trace256 storage _resolverShares_ = _resolverShares[msg.sender][resolver];
        (, uint48 latestTimestamp,) = _resolverShares_.latestCheckpoint();
        if (latestTimestamp > Time.timestamp()) {
            _resolverShares_.pop();
        }

        _resolverShares_.push(timestamp, shares);

        emit SetResolver(msg.sender, resolver, shares);
    }

    function _initializeInternal(address vault_, bytes memory data) internal override {
        (InitParams memory params) = abi.decode(data, (InitParams));

        uint48 epochDuration = IVault(vault_).epochDuration();
        if (epochDuration == 0) {
            revert VaultNotInitialized();
        }
        if (params.vetoDuration >= epochDuration) {
            revert InvalidVetoDuration();
        }

        if (params.resolverSetEpochsDelay < 3) {
            revert InvalidResolverSetEpochsDelay();
        }

        vetoDuration = params.vetoDuration;

        resolverSetEpochsDelay = params.resolverSetEpochsDelay;
    }
}
