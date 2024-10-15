// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {BaseDelegator} from "./BaseDelegator.sol";

import {IBaseDelegator} from "../../interfaces/delegator/IBaseDelegator.sol";
import {INetworkRestakeDelegator} from "../../interfaces/delegator/INetworkRestakeDelegator.sol";
import {IVault} from "../../interfaces/vault/IVault.sol";

import {Checkpoints} from "../libraries/Checkpoints.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

contract NetworkRestakeDelegator is BaseDelegator, INetworkRestakeDelegator {
    using Checkpoints for Checkpoints.Trace256;
    using Math for uint256;

    /**
     * @inheritdoc INetworkRestakeDelegator
     */
    bytes32 public constant NETWORK_LIMIT_SET_ROLE = keccak256("NETWORK_LIMIT_SET_ROLE");

    /**
     * @inheritdoc INetworkRestakeDelegator
     */
    bytes32 public constant OPERATOR_NETWORK_SHARES_SET_ROLE = keccak256("OPERATOR_NETWORK_SHARES_SET_ROLE");

    mapping(bytes32 subnetwork => Checkpoints.Trace256 value) internal _networkLimit;

    mapping(bytes32 subnetwork => Checkpoints.Trace256 shares) internal _totalOperatorNetworkShares;

    mapping(bytes32 subnetwork => mapping(address operator => Checkpoints.Trace256 shares)) internal
        _operatorNetworkShares;

    constructor(
        address networkRegistry,
        address vaultFactory,
        address operatorVaultOptInService,
        address operatorNetworkOptInService,
        address delegatorFactory,
        uint64 entityType
    )
        BaseDelegator(
            networkRegistry,
            vaultFactory,
            operatorVaultOptInService,
            operatorNetworkOptInService,
            delegatorFactory,
            entityType
        )
    {}

    /**
     * @inheritdoc INetworkRestakeDelegator
     */
    function networkLimitAt(bytes32 subnetwork, uint48 timestamp, bytes memory hint) public view returns (uint256) {
        return _networkLimit[subnetwork].upperLookupRecent(timestamp, hint);
    }

    /**
     * @inheritdoc INetworkRestakeDelegator
     */
    function networkLimit(
        bytes32 subnetwork
    ) public view returns (uint256) {
        return _networkLimit[subnetwork].latest();
    }

    /**
     * @inheritdoc INetworkRestakeDelegator
     */
    function totalOperatorNetworkSharesAt(
        bytes32 subnetwork,
        uint48 timestamp,
        bytes memory hint
    ) public view returns (uint256) {
        return _totalOperatorNetworkShares[subnetwork].upperLookupRecent(timestamp, hint);
    }

    /**
     * @inheritdoc INetworkRestakeDelegator
     */
    function totalOperatorNetworkShares(
        bytes32 subnetwork
    ) public view returns (uint256) {
        return _totalOperatorNetworkShares[subnetwork].latest();
    }

    /**
     * @inheritdoc INetworkRestakeDelegator
     */
    function operatorNetworkSharesAt(
        bytes32 subnetwork,
        address operator,
        uint48 timestamp,
        bytes memory hint
    ) public view returns (uint256) {
        return _operatorNetworkShares[subnetwork][operator].upperLookupRecent(timestamp, hint);
    }

    /**
     * @inheritdoc INetworkRestakeDelegator
     */
    function operatorNetworkShares(bytes32 subnetwork, address operator) public view returns (uint256) {
        return _operatorNetworkShares[subnetwork][operator].latest();
    }

    /**
     * @inheritdoc INetworkRestakeDelegator
     */
    function setNetworkLimit(bytes32 subnetwork, uint256 amount) external onlyRole(NETWORK_LIMIT_SET_ROLE) {
        if (amount > maxNetworkLimit[subnetwork]) {
            revert ExceedsMaxNetworkLimit();
        }

        if (networkLimit(subnetwork) == amount) {
            revert AlreadySet();
        }

        _networkLimit[subnetwork].push(Time.timestamp(), amount);

        emit SetNetworkLimit(subnetwork, amount);
    }

    /**
     * @inheritdoc INetworkRestakeDelegator
     */
    function setOperatorNetworkShares(
        bytes32 subnetwork,
        address operator,
        uint256 shares
    ) external onlyRole(OPERATOR_NETWORK_SHARES_SET_ROLE) {
        uint256 operatorNetworkShares_ = operatorNetworkShares(subnetwork, operator);
        if (operatorNetworkShares_ == shares) {
            revert AlreadySet();
        }

        _totalOperatorNetworkShares[subnetwork].push(
            Time.timestamp(), totalOperatorNetworkShares(subnetwork) - operatorNetworkShares_ + shares
        );
        _operatorNetworkShares[subnetwork][operator].push(Time.timestamp(), shares);

        emit SetOperatorNetworkShares(subnetwork, operator, shares);
    }

    function _stakeAt(
        bytes32 subnetwork,
        address operator,
        uint48 timestamp,
        bytes memory hints
    ) internal view override returns (uint256, bytes memory) {
        StakeHints memory stakesHints;
        if (hints.length > 0) {
            stakesHints = abi.decode(hints, (StakeHints));
        }

        uint256 totalOperatorNetworkSharesAt_ =
            totalOperatorNetworkSharesAt(subnetwork, timestamp, stakesHints.totalOperatorNetworkSharesHint);
        return totalOperatorNetworkSharesAt_ == 0
            ? (0, stakesHints.baseHints)
            : (
                operatorNetworkSharesAt(subnetwork, operator, timestamp, stakesHints.operatorNetworkSharesHint).mulDiv(
                    Math.min(
                        IVault(vault).activeStakeAt(timestamp, stakesHints.activeStakeHint),
                        networkLimitAt(subnetwork, timestamp, stakesHints.networkLimitHint)
                    ),
                    totalOperatorNetworkSharesAt_
                ),
                stakesHints.baseHints
            );
    }

    function _stake(bytes32 subnetwork, address operator) internal view override returns (uint256) {
        uint256 totalOperatorNetworkShares_ = totalOperatorNetworkShares(subnetwork);
        return totalOperatorNetworkShares_ == 0
            ? 0
            : operatorNetworkShares(subnetwork, operator).mulDiv(
                Math.min(IVault(vault).activeStake(), networkLimit(subnetwork)), totalOperatorNetworkShares_
            );
    }

    function _setMaxNetworkLimit(bytes32 subnetwork, uint256 amount) internal override {
        (bool exists,, uint256 latestValue) = _networkLimit[subnetwork].latestCheckpoint();
        if (exists && latestValue > amount) {
            _networkLimit[subnetwork].push(Time.timestamp(), amount);
        }
    }

    function __initialize(address, bytes memory data) internal override returns (IBaseDelegator.BaseParams memory) {
        InitParams memory params = abi.decode(data, (InitParams));

        if (
            params.baseParams.defaultAdminRoleHolder == address(0)
                && (params.networkLimitSetRoleHolders.length == 0 || params.operatorNetworkSharesSetRoleHolders.length == 0)
        ) {
            revert MissingRoleHolders();
        }

        for (uint256 i; i < params.networkLimitSetRoleHolders.length; ++i) {
            if (params.networkLimitSetRoleHolders[i] == address(0)) {
                revert ZeroAddressRoleHolder();
            }

            if (!_grantRole(NETWORK_LIMIT_SET_ROLE, params.networkLimitSetRoleHolders[i])) {
                revert DuplicateRoleHolder();
            }
        }

        for (uint256 i; i < params.operatorNetworkSharesSetRoleHolders.length; ++i) {
            if (params.operatorNetworkSharesSetRoleHolders[i] == address(0)) {
                revert ZeroAddressRoleHolder();
            }

            if (!_grantRole(OPERATOR_NETWORK_SHARES_SET_ROLE, params.operatorNetworkSharesSetRoleHolders[i])) {
                revert DuplicateRoleHolder();
            }
        }

        return params.baseParams;
    }
}
