// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {BaseDelegator} from "./BaseDelegator.sol";

import {IFullRestakeDelegator} from "src/interfaces/delegator/IFullRestakeDelegator.sol";
import {IBaseDelegator} from "src/interfaces/delegator/IBaseDelegator.sol";
import {IVault} from "src/interfaces/vault/IVault.sol";

import {Checkpoints} from "src/contracts/libraries/Checkpoints.sol";

import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

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

    mapping(address network => Checkpoints.Trace256 value) private _networkLimit;

    mapping(address network => Checkpoints.Trace256 value) private _totalOperatorNetworkLimit;

    mapping(address network => mapping(address operator => Checkpoints.Trace256 value)) private _operatorNetworkLimit;

    constructor(
        address networkRegistry,
        address vaultFactory,
        address operatorVaultOptInService,
        address operatorNetworkOptInService,
        address delegatorFactory
    )
        BaseDelegator(
            networkRegistry,
            vaultFactory,
            operatorVaultOptInService,
            operatorNetworkOptInService,
            delegatorFactory
        )
    {}

    /**
     * @inheritdoc IFullRestakeDelegator
     */
    function networkLimitAt(address network, uint48 timestamp) public view returns (uint256) {
        return _networkLimit[network].upperLookupRecent(timestamp);
    }

    /**
     * @inheritdoc IFullRestakeDelegator
     */
    function networkLimit(address network) public view returns (uint256) {
        return networkLimitAt(network, Time.timestamp());
    }

    /**
     * @inheritdoc IFullRestakeDelegator
     */
    function totalOperatorNetworkLimitAt(address network, uint48 timestamp) public view returns (uint256) {
        return _totalOperatorNetworkLimit[network].upperLookupRecent(timestamp);
    }

    /**
     * @inheritdoc IFullRestakeDelegator
     */
    function totalOperatorNetworkLimit(address network) public view returns (uint256) {
        return totalOperatorNetworkLimitAt(network, Time.timestamp());
    }

    /**
     * @inheritdoc IFullRestakeDelegator
     */
    function operatorNetworkLimitAt(
        address network,
        address operator,
        uint48 timestamp
    ) public view returns (uint256) {
        return _operatorNetworkLimit[network][operator].upperLookupRecent(timestamp);
    }

    /**
     * @inheritdoc IFullRestakeDelegator
     */
    function operatorNetworkLimit(address network, address operator) public view returns (uint256) {
        return operatorNetworkLimitAt(network, operator, Time.timestamp());
    }

    /**
     * @inheritdoc IBaseDelegator
     */
    function networkStakeIn(
        address network,
        uint48 duration
    ) public view override(IBaseDelegator, BaseDelegator) returns (uint256) {
        return Math.min(
            IVault(vault).totalSupplyIn(duration),
            Math.min(
                networkLimitAt(network, Time.timestamp() + duration),
                totalOperatorNetworkLimitAt(network, Time.timestamp() + duration)
            )
        );
    }

    /**
     * @inheritdoc IBaseDelegator
     */
    function networkStake(address network) public view override(IBaseDelegator, BaseDelegator) returns (uint256) {
        return
            Math.min(IVault(vault).totalSupply(), Math.min(networkLimit(network), totalOperatorNetworkLimit(network)));
    }

    /**
     * @inheritdoc IBaseDelegator
     */
    function operatorNetworkStakeIn(
        address network,
        address operator,
        uint48 duration
    ) public view override(IBaseDelegator, BaseDelegator) returns (uint256) {
        return Math.min(
            IVault(vault).totalSupplyIn(duration),
            Math.min(
                networkLimitAt(network, Time.timestamp() + duration),
                operatorNetworkLimitAt(network, operator, Time.timestamp() + duration)
            )
        );
    }

    /**
     * @inheritdoc IBaseDelegator
     */
    function operatorNetworkStake(
        address network,
        address operator
    ) public view override(IBaseDelegator, BaseDelegator) returns (uint256) {
        return Math.min(
            IVault(vault).totalSupply(), Math.min(networkLimit(network), operatorNetworkLimit(network, operator))
        );
    }

    /**
     * @inheritdoc IFullRestakeDelegator
     */
    function setNetworkLimit(address network, uint256 amount) external onlyRole(NETWORK_LIMIT_SET_ROLE) {
        if (amount > maxNetworkLimit[network]) {
            revert ExceedsMaxNetworkLimit();
        }

        uint48 epochDuration = IVault(vault).epochDuration();
        uint48 nextEpochStart = IVault(vault).currentEpochStart() + epochDuration;
        (, uint48 checkpointTimestamp,,) = _networkLimit[network].upperLookupRecentCheckpoint(nextEpochStart);

        uint48 timestamp = checkpointTimestamp < Time.timestamp() && amount > networkLimit(network)
            ? Time.timestamp()
            : nextEpochStart + epochDuration;

        _insertCheckpoint(_networkLimit[network], timestamp, amount);

        emit SetNetworkLimit(network, amount);
    }

    /**
     * @inheritdoc IFullRestakeDelegator
     */
    function setOperatorNetworkLimit(
        address network,
        address operator,
        uint256 amount
    ) external onlyRole(OPERATOR_NETWORK_LIMIT_SET_ROLE) {
        uint48 epochDuration = IVault(vault).epochDuration();
        uint48 nextEpochStart = IVault(vault).currentEpochStart() + epochDuration;
        (, uint48 checkpointTimestamp,,) =
            _operatorNetworkLimit[network][operator].upperLookupRecentCheckpoint(nextEpochStart);

        uint48 timestamp;
        uint256 totalOperatorNetworkLimit_;
        if (checkpointTimestamp < Time.timestamp() && amount > operatorNetworkLimit(network, operator)) {
            timestamp = Time.timestamp();
            totalOperatorNetworkLimit_ =
                totalOperatorNetworkLimit(network) - operatorNetworkLimit(network, operator) + amount;
        } else {
            timestamp = nextEpochStart + epochDuration;
            totalOperatorNetworkLimit_ = _totalOperatorNetworkLimit[network].latest()
                - _operatorNetworkLimit[network][operator].latest() + amount;
        }

        _insertCheckpoint(_totalOperatorNetworkLimit[network], timestamp, totalOperatorNetworkLimit_);

        _insertCheckpoint(_operatorNetworkLimit[network][operator], timestamp, amount);

        emit SetOperatorNetworkLimit(network, operator, amount);
    }

    function _minOperatorNetworkStakeAt(
        address network,
        address operator,
        uint48 timestamp
    ) internal view override returns (uint256) {
        uint48 epochDuration = IVault(vault).epochDuration();

        return Math.min(
            IVault(vault).activeSupplyAt(timestamp),
            Math.min(
                Math.min(networkLimitAt(network, timestamp), operatorNetworkLimitAt(network, operator, timestamp)),
                Math.min(
                    networkLimitAt(network, timestamp + epochDuration),
                    operatorNetworkLimitAt(network, operator, timestamp + epochDuration)
                )
            )
        );
    }

    function _minOperatorNetworkStake(address network, address operator) internal view override returns (uint256) {
        uint48 epochDuration = IVault(vault).epochDuration();

        return Math.min(
            IVault(vault).activeSupply(),
            Math.min(
                Math.min(networkLimit(network), operatorNetworkLimit(network, operator)),
                Math.min(
                    networkLimitAt(network, Time.timestamp() + epochDuration),
                    operatorNetworkLimitAt(network, operator, Time.timestamp() + epochDuration)
                )
            )
        );
    }

    function _setMaxNetworkLimit(uint256 amount) internal override {
        Checkpoints.Trace256 storage _networkLimit_ = _networkLimit[msg.sender];
        (bool exists, uint48 latestTimestamp1, uint256 latestValue1) = _networkLimit_.latestCheckpoint();
        if (exists) {
            if (Time.timestamp() < latestTimestamp1) {
                _networkLimit_.pop();
                (, uint48 latestTimestamp2, uint256 latestValue2) = _networkLimit_.latestCheckpoint();
                if (Time.timestamp() < latestTimestamp2) {
                    _networkLimit_.pop();
                    _networkLimit_.push(Time.timestamp(), Math.min(_networkLimit_.latest(), amount));
                    _networkLimit_.push(latestTimestamp2, Math.min(latestValue2, amount));
                } else {
                    _networkLimit_.push(Time.timestamp(), Math.min(latestValue2, amount));
                }
                _networkLimit_.push(latestTimestamp1, Math.min(latestValue1, amount));
            } else {
                _networkLimit_.push(Time.timestamp(), Math.min(latestValue1, amount));
            }
        }
    }

    function _onSlash(address network, address operator, uint256 slashedAmount) internal override {
        uint256 networkLimit_ = networkLimit(network);
        if (networkLimit_ != type(uint256).max) {
            _insertCheckpoint(_networkLimit[network], Time.timestamp(), networkLimit_ - slashedAmount);
        }

        _insertCheckpoint(
            _totalOperatorNetworkLimit[network], Time.timestamp(), totalOperatorNetworkLimit(network) - slashedAmount
        );

        _insertCheckpoint(
            _operatorNetworkLimit[network][operator],
            Time.timestamp(),
            operatorNetworkLimit(network, operator) - slashedAmount
        );
    }

    function _initializeInternal(
        address,
        bytes memory data
    ) internal override returns (IBaseDelegator.BaseParams memory) {
        InitParams memory params = abi.decode(data, (InitParams));

        if (
            params.baseParams.defaultAdminRoleHolder == address(0)
                && (
                    params.networkLimitSetRoleHolder == address(0) || params.operatorNetworkLimitSetRoleHolder == address(0)
                )
        ) {
            revert MissingRoleHolders();
        }

        if (params.networkLimitSetRoleHolder != address(0)) {
            _grantRole(NETWORK_LIMIT_SET_ROLE, params.networkLimitSetRoleHolder);
        }
        if (params.operatorNetworkLimitSetRoleHolder != address(0)) {
            _grantRole(OPERATOR_NETWORK_LIMIT_SET_ROLE, params.operatorNetworkLimitSetRoleHolder);
        }

        return params.baseParams;
    }
}
