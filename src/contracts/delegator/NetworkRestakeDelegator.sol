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
    function networkLimitAt(address network, uint48 timestamp) public view returns (uint256) {
        return _networkLimit[network].upperLookupRecent(timestamp);
    }

    /**
     * @inheritdoc INetworkRestakeDelegator
     */
    function networkLimit(address network) public view returns (uint256) {
        return _networkLimit[network].latest();
    }

    /**
     * @inheritdoc INetworkRestakeDelegator
     */
    function totalOperatorNetworkSharesAt(address network, uint48 timestamp) public view returns (uint256) {
        return _totalOperatorNetworkShares[network].upperLookupRecent(timestamp);
    }

    /**
     * @inheritdoc INetworkRestakeDelegator
     */
    function totalOperatorNetworkShares(address network) public view returns (uint256) {
        return _totalOperatorNetworkShares[network].latest();
    }

    /**
     * @inheritdoc INetworkRestakeDelegator
     */
    function operatorNetworkSharesAt(
        address network,
        address operator,
        uint48 timestamp
    ) public view returns (uint256) {
        return _operatorNetworkShares[network][operator].upperLookupRecent(timestamp);
    }

    /**
     * @inheritdoc INetworkRestakeDelegator
     */
    function operatorNetworkShares(address network, address operator) public view returns (uint256) {
        return _operatorNetworkShares[network][operator].latest();
    }

    /**
     * @inheritdoc INetworkRestakeDelegator
     */
    function setNetworkLimit(address network, uint256 amount) external onlyRole(NETWORK_LIMIT_SET_ROLE) {
        if (amount > maxNetworkLimit[network]) {
            revert ExceedsMaxNetworkLimit();
        }

        _setNetworkLimit(network, amount);

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
        _setOperatorNetworkShares(network, operator, shares);

        emit SetOperatorNetworkShares(network, operator, shares);
    }

    function _setNetworkLimit(address network, uint256 amount) internal {
        _networkLimit[network].push(Time.timestamp(), amount);
    }

    function _setOperatorNetworkShares(address network, address operator, uint256 shares) internal {
        _totalOperatorNetworkShares[network].push(
            Time.timestamp(), totalOperatorNetworkShares(network) - operatorNetworkShares(network, operator) + shares
        );
        _operatorNetworkShares[network][operator].push(Time.timestamp(), shares);
    }

    function _stakeAtHints(
        address network,
        address operator,
        uint48 timestamp,
        StakeBaseHints memory baseHints
    ) internal view override returns (bytes memory) {
        (,,, uint32 activeStakeHint) = IVault(vault).activeStakeCheckpointAt(timestamp);
        (,,, uint32 networkLimitHint) = _networkLimit[network].upperLookupRecentCheckpoint(timestamp);
        (,,, uint32 operatorNetworkSharesHint) =
            _operatorNetworkShares[network][operator].upperLookupRecentCheckpoint(timestamp);
        (,,, uint32 totalOperatorNetworkSharesHint) =
            _totalOperatorNetworkShares[network].upperLookupRecentCheckpoint(timestamp);

        return abi.encode(
            StakeHints({
                baseHints: baseHints,
                activeStakeHint: activeStakeHint,
                networkLimitHint: networkLimitHint,
                operatorNetworkSharesHint: operatorNetworkSharesHint,
                totalOperatorNetworkSharesHint: totalOperatorNetworkSharesHint
            })
        );
    }

    function _stakeAt(
        address network,
        address operator,
        uint48 timestamp,
        bytes memory hints
    ) internal view override returns (uint256, IBaseDelegator.StakeBaseHints memory) {
        INetworkRestakeDelegator.StakeHints memory hints_ = abi.decode(hints, (INetworkRestakeDelegator.StakeHints));

        uint256 totalOperatorNetworkSharesAt_ = _operatorNetworkShares[network][operator].upperLookupRecent(
            timestamp, hints_.totalOperatorNetworkSharesHint
        );
        return totalOperatorNetworkSharesAt_ == 0
            ? (0, hints_.baseHints)
            : (
                _operatorNetworkShares[network][operator].upperLookupRecent(timestamp, hints_.operatorNetworkSharesHint)
                    .mulDiv(
                    Math.min(
                        IVault(vault).activeStakeAt(timestamp, hints_.activeStakeHint),
                        _networkLimit[network].upperLookupRecent(timestamp, hints_.networkLimitHint)
                    ),
                    totalOperatorNetworkSharesAt_
                ),
                hints_.baseHints
            );
    }

    function _stakeAt(address network, address operator, uint48 timestamp) internal view override returns (uint256) {
        uint256 totalOperatorNetworkSharesAt_ = totalOperatorNetworkSharesAt(network, timestamp);
        return totalOperatorNetworkSharesAt_ == 0
            ? 0
            : operatorNetworkSharesAt(network, operator, timestamp).mulDiv(
                Math.min(IVault(vault).activeStakeAt(timestamp), networkLimitAt(network, timestamp)),
                totalOperatorNetworkSharesAt_
            );
    }

    function _stake(address network, address operator) internal view override returns (uint256) {
        uint256 totalOperatorNetworkShares_ = totalOperatorNetworkShares(network);
        return totalOperatorNetworkShares_ == 0
            ? 0
            : operatorNetworkShares(network, operator).mulDiv(
                Math.min(IVault(vault).activeStake(), networkLimit(network)), totalOperatorNetworkShares_
            );
    }

    function _setMaxNetworkLimit(uint256 amount) internal override {
        (bool exists,, uint256 latestValue) = _networkLimit[msg.sender].latestCheckpoint();
        if (exists) {
            _networkLimit[msg.sender].push(Time.timestamp(), Math.min(latestValue, amount));
        }
    }

    function _initializeInternal(
        address,
        bytes memory data
    ) internal override returns (IBaseDelegator.BaseParams memory) {
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

            if (hasRole(NETWORK_LIMIT_SET_ROLE, params.networkLimitSetRoleHolders[i])) {
                revert DuplicateRoleHolder();
            }

            _grantRole(NETWORK_LIMIT_SET_ROLE, params.networkLimitSetRoleHolders[i]);
        }

        for (uint256 i; i < params.operatorNetworkSharesSetRoleHolders.length; ++i) {
            if (params.operatorNetworkSharesSetRoleHolders[i] == address(0)) {
                revert ZeroAddressRoleHolder();
            }

            if (hasRole(OPERATOR_NETWORK_SHARES_SET_ROLE, params.operatorNetworkSharesSetRoleHolders[i])) {
                revert DuplicateRoleHolder();
            }

            _grantRole(OPERATOR_NETWORK_SHARES_SET_ROLE, params.operatorNetworkSharesSetRoleHolders[i]);
        }

        return params.baseParams;
    }
}
