// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {BaseDelegator} from "./BaseDelegator.sol";

import {IBaseDelegator} from "../../interfaces/delegator/IBaseDelegator.sol";
import {IOperatorSpecificDelegator} from "../../interfaces/delegator/IOperatorSpecificDelegator.sol";
import {IRegistry} from "../../interfaces/common/IRegistry.sol";
import {IVault} from "../../interfaces/vault/IVault.sol";

import {Checkpoints} from "../libraries/Checkpoints.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

contract OperatorSpecificDelegator is BaseDelegator, IOperatorSpecificDelegator {
    using Checkpoints for Checkpoints.Trace256;
    using Math for uint256;

    /**
     * @inheritdoc IOperatorSpecificDelegator
     */
    bytes32 public constant NETWORK_LIMIT_SET_ROLE = keccak256("NETWORK_LIMIT_SET_ROLE");

    /**
     * @inheritdoc IOperatorSpecificDelegator
     */
    address public immutable OPERATOR_REGISTRY;

    mapping(bytes32 subnetwork => Checkpoints.Trace256 value) internal _networkLimit;

    /**
     * @inheritdoc IOperatorSpecificDelegator
     */
    address public operator;

    constructor(
        address operatorRegistry,
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
    {
        OPERATOR_REGISTRY = operatorRegistry;
    }

    /**
     * @inheritdoc IOperatorSpecificDelegator
     */
    function networkLimitAt(bytes32 subnetwork, uint48 timestamp, bytes memory hint) public view returns (uint256) {
        return _networkLimit[subnetwork].upperLookupRecent(timestamp, hint);
    }

    /**
     * @inheritdoc IOperatorSpecificDelegator
     */
    function networkLimit(
        bytes32 subnetwork
    ) public view returns (uint256) {
        return _networkLimit[subnetwork].latest();
    }

    /**
     * @inheritdoc IOperatorSpecificDelegator
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

    function _stakeAt(
        bytes32 subnetwork,
        address operator_,
        uint48 timestamp,
        bytes memory hints
    ) internal view override returns (uint256, bytes memory) {
        StakeHints memory stakesHints;
        if (hints.length > 0) {
            stakesHints = abi.decode(hints, (StakeHints));
        }

        if (operator != operator_) {
            return (0, stakesHints.baseHints);
        }

        return (
            Math.min(
                IVault(vault).activeStakeAt(timestamp, stakesHints.activeStakeHint),
                networkLimitAt(subnetwork, timestamp, stakesHints.networkLimitHint)
            ),
            stakesHints.baseHints
        );
    }

    function _stake(bytes32 subnetwork, address operator_) internal view override returns (uint256) {
        if (operator != operator_) {
            return 0;
        }

        return Math.min(IVault(vault).activeStake(), networkLimit(subnetwork));
    }

    function _setMaxNetworkLimit(bytes32 subnetwork, uint256 amount) internal override {
        (bool exists,, uint256 latestValue) = _networkLimit[subnetwork].latestCheckpoint();
        if (exists && latestValue > amount) {
            _networkLimit[subnetwork].push(Time.timestamp(), amount);
        }
    }

    function __initialize(address, bytes memory data) internal override returns (IBaseDelegator.BaseParams memory) {
        InitParams memory params = abi.decode(data, (InitParams));

        if (params.baseParams.defaultAdminRoleHolder == address(0) && params.networkLimitSetRoleHolders.length == 0) {
            revert MissingRoleHolders();
        }

        if (!IRegistry(OPERATOR_REGISTRY).isEntity(params.operator)) {
            revert NotOperator();
        }

        for (uint256 i; i < params.networkLimitSetRoleHolders.length; ++i) {
            if (params.networkLimitSetRoleHolders[i] == address(0)) {
                revert ZeroAddressRoleHolder();
            }

            if (!_grantRole(NETWORK_LIMIT_SET_ROLE, params.networkLimitSetRoleHolders[i])) {
                revert DuplicateRoleHolder();
            }
        }

        operator = params.operator;

        return params.baseParams;
    }
}
