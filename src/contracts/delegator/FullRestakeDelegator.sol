// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {BaseDelegator} from "./BaseDelegator.sol";

import {IBaseDelegator} from "../../interfaces/delegator/IBaseDelegator.sol";
import {IFullRestakeDelegator} from "../../interfaces/delegator/IFullRestakeDelegator.sol";
import {IVault} from "../../interfaces/vault/IVault.sol";

import {Checkpoints} from "../libraries/Checkpoints.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

contract FullRestakeDelegator is BaseDelegator, IFullRestakeDelegator {
    using Checkpoints for Checkpoints.Trace256;
    using Math for uint256;

    /**
     * @inheritdoc IFullRestakeDelegator
     */
    bytes32 public constant NETWORK_LIMIT_SET_ROLE = keccak256("NETWORK_LIMIT_SET_ROLE");

    /**
     * @inheritdoc IFullRestakeDelegator
     */
    bytes32 public constant OPERATOR_NETWORK_LIMIT_SET_ROLE = keccak256("OPERATOR_NETWORK_LIMIT_SET_ROLE");

    mapping(bytes32 subnetwork => Checkpoints.Trace256 value) internal _networkLimit;

    mapping(bytes32 subnetwork => mapping(address operator => Checkpoints.Trace256 value)) internal
        _operatorNetworkLimit;

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
     * @inheritdoc IFullRestakeDelegator
     */
    function networkLimitAt(bytes32 subnetwork, uint48 timestamp, bytes memory hint) public view returns (uint256) {
        return _networkLimit[subnetwork].upperLookupRecent(timestamp, hint);
    }

    /**
     * @inheritdoc IFullRestakeDelegator
     */
    function networkLimit(
        bytes32 subnetwork
    ) public view returns (uint256) {
        return _networkLimit[subnetwork].latest();
    }

    /**
     * @inheritdoc IFullRestakeDelegator
     */
    function operatorNetworkLimitAt(
        bytes32 subnetwork,
        address operator,
        uint48 timestamp,
        bytes memory hint
    ) public view returns (uint256) {
        return _operatorNetworkLimit[subnetwork][operator].upperLookupRecent(timestamp, hint);
    }

    /**
     * @inheritdoc IFullRestakeDelegator
     */
    function operatorNetworkLimit(bytes32 subnetwork, address operator) public view returns (uint256) {
        return _operatorNetworkLimit[subnetwork][operator].latest();
    }

    /**
     * @inheritdoc IFullRestakeDelegator
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
     * @inheritdoc IFullRestakeDelegator
     */
    function setOperatorNetworkLimit(
        bytes32 subnetwork,
        address operator,
        uint256 amount
    ) external onlyRole(OPERATOR_NETWORK_LIMIT_SET_ROLE) {
        if (operatorNetworkLimit(subnetwork, operator) == amount) {
            revert AlreadySet();
        }

        _operatorNetworkLimit[subnetwork][operator].push(Time.timestamp(), amount);

        emit SetOperatorNetworkLimit(subnetwork, operator, amount);
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

        return (
            Math.min(
                IVault(vault).activeStakeAt(timestamp, stakesHints.activeStakeHint),
                Math.min(
                    networkLimitAt(subnetwork, timestamp, stakesHints.networkLimitHint),
                    operatorNetworkLimitAt(subnetwork, operator, timestamp, stakesHints.operatorNetworkLimitHint)
                )
            ),
            stakesHints.baseHints
        );
    }

    function _stake(bytes32 subnetwork, address operator) internal view override returns (uint256) {
        return Math.min(
            IVault(vault).activeStake(), Math.min(networkLimit(subnetwork), operatorNetworkLimit(subnetwork, operator))
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
                && (params.networkLimitSetRoleHolders.length == 0 || params.operatorNetworkLimitSetRoleHolders.length == 0)
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

        for (uint256 i; i < params.operatorNetworkLimitSetRoleHolders.length; ++i) {
            if (params.operatorNetworkLimitSetRoleHolders[i] == address(0)) {
                revert ZeroAddressRoleHolder();
            }

            if (!_grantRole(OPERATOR_NETWORK_LIMIT_SET_ROLE, params.operatorNetworkLimitSetRoleHolders[i])) {
                revert DuplicateRoleHolder();
            }
        }

        return params.baseParams;
    }
}
