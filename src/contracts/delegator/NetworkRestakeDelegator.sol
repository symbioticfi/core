// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {BaseDelegator} from "./BaseDelegator.sol";

import {INetworkRestakeDelegator} from "src/interfaces/delegator/INetworkRestakeDelegator.sol";
import {IBaseDelegator} from "src/interfaces/delegator/IBaseDelegator.sol";
import {IVault} from "src/interfaces/vault/IVault.sol";

import {Checkpoints} from "src/contracts/libraries/Checkpoints.sol";

import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

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

    mapping(address network => Checkpoints.Trace256 value) private _networkLimit;

    mapping(address network => Checkpoints.Trace256 shares) private _totalOperatorNetworkShares;

    mapping(address network => mapping(address operator => Checkpoints.Trace256 shares)) private _operatorNetworkShares;

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
     * @inheritdoc INetworkRestakeDelegator
     */
    function networkLimitIn(address network, uint48 duration) public view returns (uint256) {
        return _networkLimit[network].upperLookupRecent(Time.timestamp() + duration);
    }

    /**
     * @inheritdoc INetworkRestakeDelegator
     */
    function networkLimit(address network) public view returns (uint256) {
        return _networkLimit[network].upperLookupRecent(Time.timestamp());
    }

    /**
     * @inheritdoc INetworkRestakeDelegator
     */
    function totalOperatorNetworkSharesIn(address network, uint48 duration) public view returns (uint256) {
        return _totalOperatorNetworkShares[network].upperLookupRecent(Time.timestamp() + duration);
    }

    /**
     * @inheritdoc INetworkRestakeDelegator
     */
    function totalOperatorNetworkShares(address network) public view returns (uint256) {
        return _totalOperatorNetworkShares[network].upperLookupRecent(Time.timestamp());
    }

    /**
     * @inheritdoc INetworkRestakeDelegator
     */
    function operatorNetworkSharesIn(
        address network,
        address operator,
        uint48 duration
    ) public view returns (uint256) {
        return _operatorNetworkShares[network][operator].upperLookupRecent(Time.timestamp() + duration);
    }

    /**
     * @inheritdoc INetworkRestakeDelegator
     */
    function operatorNetworkShares(address network, address operator) public view returns (uint256) {
        return _operatorNetworkShares[network][operator].upperLookupRecent(Time.timestamp());
    }

    /**
     * @inheritdoc IBaseDelegator
     */
    function networkStakeIn(
        address network,
        uint48 duration
    ) public view override(IBaseDelegator, BaseDelegator) returns (uint256) {
        if (totalOperatorNetworkSharesIn(network, duration) == 0) {
            return 0;
        }
        return Math.min(IVault(vault).totalSupplyIn(duration), networkLimitIn(network, duration));
    }

    /**
     * @inheritdoc IBaseDelegator
     */
    function networkStake(address network) public view override(IBaseDelegator, BaseDelegator) returns (uint256) {
        if (totalOperatorNetworkShares(network) == 0) {
            return 0;
        }
        return Math.min(IVault(vault).totalSupply(), networkLimit(network));
    }

    /**
     * @inheritdoc IBaseDelegator
     */
    function operatorNetworkStakeIn(
        address network,
        address operator,
        uint48 duration
    ) public view override(IBaseDelegator, BaseDelegator) returns (uint256) {
        uint256 totalOperatorNetworkSharesIn_ = totalOperatorNetworkSharesIn(network, duration);
        if (totalOperatorNetworkSharesIn_ == 0) {
            return 0;
        }
        return operatorNetworkSharesIn(network, operator, duration).mulDiv(
            networkStakeIn(network, duration), totalOperatorNetworkSharesIn_
        );
    }

    /**
     * @inheritdoc IBaseDelegator
     */
    function operatorNetworkStake(
        address network,
        address operator
    ) public view override(IBaseDelegator, BaseDelegator) returns (uint256) {
        uint256 totalOperatorNetworkShares_ = totalOperatorNetworkShares(network);
        if (totalOperatorNetworkShares_ == 0) {
            return 0;
        }
        return operatorNetworkShares(network, operator).mulDiv(networkStake(network), totalOperatorNetworkShares_);
    }

    /**
     * @inheritdoc INetworkRestakeDelegator
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
     * @inheritdoc INetworkRestakeDelegator
     */
    function setOperatorNetworkShares(
        address network,
        address operator,
        uint256 shares
    ) external onlyRole(OPERATOR_NETWORK_SHARES_SET_ROLE) {
        uint48 timestamp = IVault(vault).currentEpochStart() + 2 * IVault(vault).epochDuration();

        _totalOperatorNetworkShares[network].push(
            timestamp,
            _totalOperatorNetworkShares[network].latest() - _operatorNetworkShares[network][operator].latest() + shares
        );

        _operatorNetworkShares[network][operator].push(timestamp, shares);

        emit SetOperatorNetworkShares(network, operator, shares);
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

        uint256 operatorNetworkShares_ = operatorNetworkShares(network, operator);
        uint256 operatorSlashedShares =
            slashedAmount.mulDiv(operatorNetworkShares_, operatorNetworkStake(network, operator), Math.Rounding.Ceil);

        _totalOperatorNetworkShares[network].push(
            Time.timestamp(), totalOperatorNetworkShares(network) - operatorSlashedShares
        );

        _operatorNetworkShares[network][operator].push(Time.timestamp(), operatorNetworkShares_ - operatorSlashedShares);
    }

    function _initializeInternal(
        address,
        bytes memory data
    ) internal override returns (IBaseDelegator.BaseParams memory) {
        InitParams memory params = abi.decode(data, (InitParams));

        if (
            params.baseParams.defaultAdminRoleHolder == address(0)
                && (
                    params.networkLimitSetRoleHolder == address(0)
                        || params.operatorNetworkSharesSetRoleHolder == address(0)
                )
        ) {
            revert MissingRoleHolders();
        }

        if (params.networkLimitSetRoleHolder != address(0)) {
            _grantRole(NETWORK_LIMIT_SET_ROLE, params.networkLimitSetRoleHolder);
        }
        if (params.operatorNetworkSharesSetRoleHolder != address(0)) {
            _grantRole(OPERATOR_NETWORK_SHARES_SET_ROLE, params.operatorNetworkSharesSetRoleHolder);
        }

        return params.baseParams;
    }
}
