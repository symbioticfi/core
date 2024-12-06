// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {BaseDelegator} from "./BaseDelegator.sol";

import {IBaseDelegator} from "../../interfaces/delegator/IBaseDelegator.sol";
import {IOperatorNetworkSpecificDelegator} from "../../interfaces/delegator/IOperatorNetworkSpecificDelegator.sol";
import {IRegistry} from "../../interfaces/common/IRegistry.sol";
import {IVault} from "../../interfaces/vault/IVault.sol";

import {Checkpoints} from "../libraries/Checkpoints.sol";
import {Subnetwork} from "../libraries/Subnetwork.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

contract OperatorNetworkSpecificDelegator is BaseDelegator, IOperatorNetworkSpecificDelegator {
    using Checkpoints for Checkpoints.Trace256;
    using Math for uint256;
    using Subnetwork for bytes32;

    /**
     * @inheritdoc IOperatorNetworkSpecificDelegator
     */
    address public immutable OPERATOR_REGISTRY;

    mapping(bytes32 subnetwork => Checkpoints.Trace256 value) internal _maxNetworkLimit;

    /**
     * @inheritdoc IOperatorNetworkSpecificDelegator
     */
    address public network;

    /**
     * @inheritdoc IOperatorNetworkSpecificDelegator
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
     * @inheritdoc IOperatorNetworkSpecificDelegator
     */
    function maxNetworkLimitAt(bytes32 subnetwork, uint48 timestamp, bytes memory hint) public view returns (uint256) {
        return _maxNetworkLimit[subnetwork].upperLookupRecent(timestamp, hint);
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

        if (network != subnetwork.network() || operator != operator_) {
            return (0, stakesHints.baseHints);
        }

        return (
            Math.min(
                IVault(vault).activeStakeAt(timestamp, stakesHints.activeStakeHint),
                maxNetworkLimitAt(subnetwork, timestamp, stakesHints.maxNetworkLimitHint)
            ),
            stakesHints.baseHints
        );
    }

    function _stake(bytes32 subnetwork, address operator_) internal view override returns (uint256) {
        if (network != subnetwork.network() || operator != operator_) {
            return 0;
        }

        return Math.min(IVault(vault).activeStake(), maxNetworkLimit[subnetwork]);
    }

    function _setMaxNetworkLimit(bytes32 subnetwork, uint256 amount) internal override {
        if (network != subnetwork.network()) {
            revert InvalidNetwork();
        }
        _maxNetworkLimit[subnetwork].push(Time.timestamp(), amount);
    }

    function __initialize(address, bytes memory data) internal override returns (IBaseDelegator.BaseParams memory) {
        InitParams memory params = abi.decode(data, (InitParams));

        if (!IRegistry(NETWORK_REGISTRY).isEntity(params.network)) {
            revert NotNetwork();
        }

        if (!IRegistry(OPERATOR_REGISTRY).isEntity(params.operator)) {
            revert NotOperator();
        }

        network = params.network;
        operator = params.operator;

        return params.baseParams;
    }
}
