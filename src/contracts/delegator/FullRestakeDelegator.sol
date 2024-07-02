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
    function networkLimitIn(address network, uint48 duration) public view returns (uint256) {
        return _networkLimit[network].upperLookupRecent(Time.timestamp() + duration);
    }

    /**
     * @inheritdoc IFullRestakeDelegator
     */
    function networkLimit(address network) public view returns (uint256) {
        return _networkLimit[network].upperLookupRecent(Time.timestamp());
    }

    /**
     * @inheritdoc IFullRestakeDelegator
     */
    function totalOperatorNetworkLimitIn(address network, uint48 duration) public view returns (uint256) {
        return _totalOperatorNetworkLimit[network].upperLookupRecent(Time.timestamp() + duration);
    }

    /**
     * @inheritdoc IFullRestakeDelegator
     */
    function totalOperatorNetworkLimit(address network) public view returns (uint256) {
        return _totalOperatorNetworkLimit[network].upperLookupRecent(Time.timestamp());
    }

    /**
     * @inheritdoc IFullRestakeDelegator
     */
    function operatorNetworkLimitIn(address network, address operator, uint48 duration) public view returns (uint256) {
        return _operatorNetworkLimit[network][operator].upperLookupRecent(Time.timestamp() + duration);
    }

    /**
     * @inheritdoc IFullRestakeDelegator
     */
    function operatorNetworkLimit(address network, address operator) public view returns (uint256) {
        return _operatorNetworkLimit[network][operator].upperLookupRecent(Time.timestamp());
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
            Math.min(networkLimitIn(network, duration), totalOperatorNetworkLimitIn(network, duration))
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
        return Math.min(networkStakeIn(network, duration), operatorNetworkLimitIn(network, operator, duration));
    }

    /**
     * @inheritdoc IBaseDelegator
     */
    function operatorNetworkStake(
        address network,
        address operator
    ) public view override(IBaseDelegator, BaseDelegator) returns (uint256) {
        return Math.min(networkStake(network), operatorNetworkLimit(network, operator));
    }

    /**
     * @inheritdoc IFullRestakeDelegator
     */
    function setNetworkLimit(address network, uint256 amount) external onlyRole(NETWORK_LIMIT_SET_ROLE) {
        if (amount > maxNetworkLimit[network]) {
            revert ExceedsMaxNetworkLimit();
        }

        uint48 timestamp = amount > networkLimit(network)
            ? Time.timestamp()
            : IVault(vault).currentEpochStart() + 2 * IVault(vault).epochDuration();

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
        uint48 timestamp;
        uint256 totalOperatorNetworkLimit_;
        if (amount > operatorNetworkLimit(network, operator)) {
            timestamp = Time.timestamp();
            totalOperatorNetworkLimit_ =
                totalOperatorNetworkLimit(network) + amount - operatorNetworkLimit(network, operator);
        } else {
            timestamp = IVault(vault).currentEpochStart() + 2 * IVault(vault).epochDuration();
            totalOperatorNetworkLimit_ = _totalOperatorNetworkLimit[network].latest() + amount
                - _operatorNetworkLimit[network][operator].latest();
        }

        _insertCheckpoint(_totalOperatorNetworkLimit[network], timestamp, totalOperatorNetworkLimit_);

        _insertCheckpoint(_operatorNetworkLimit[network][operator], timestamp, amount);

        emit SetOperatorNetworkLimit(network, operator, amount);
    }

    function _setMaxNetworkLimit(uint256 amount) internal override {
        Checkpoints.Trace256 storage _networkLimit_ = _networkLimit[msg.sender];
        (, uint48 latestTimestamp1, uint256 latestValue1) = _networkLimit_.latestCheckpoint();
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

    function _onSlash(address network, address operator, uint256 slashedAmount) internal override {
        uint256 networkLimit_ = networkLimit(network);
        if (networkLimit_ != type(uint256).max) {
            _networkLimit[network].push(Time.timestamp(), networkLimit_ - slashedAmount);
        }

        _totalOperatorNetworkLimit[network].push(Time.timestamp(), totalOperatorNetworkLimit(network) - slashedAmount);

        _operatorNetworkLimit[network][operator].push(
            Time.timestamp(), operatorNetworkLimit(network, operator) - slashedAmount
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
