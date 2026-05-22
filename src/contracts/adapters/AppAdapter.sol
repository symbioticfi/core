// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Adapter} from "./Adapter.sol";

import {Subnetwork} from "../libraries/Subnetwork.sol";

import {IAdapter} from "../../interfaces/adapters/IAdapter.sol";
import {IAppAdapter} from "../../interfaces/adapters/IAppAdapter.sol";
import {IUniversalDelegator} from "../../interfaces/delegator/IUniversalDelegator.sol";
import {INetworkMiddlewareService} from "../../interfaces/service/INetworkMiddlewareService.sol";
import {IVaultV2} from "../../interfaces/vault/IVaultV2.sol";

import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title AppAdapter
/// @notice Single network-operator guarantee adapter.
contract AppAdapter is Adapter, IAppAdapter {
    using Math for uint256;
    using SafeERC20 for IERC20;
    using Subnetwork for bytes32;
    using Checkpoints for Checkpoints.Trace256;
    using Checkpoints for Checkpoints.Trace208;

    struct Stake {
        uint256 initialStake;
        Checkpoints.Trace256 debt;
        Checkpoints.Trace256 slashed;
    }

    Stake[] internal _stakes;
    Checkpoints.Trace208 internal _timestampToStake;
    Checkpoints.Trace256 internal _timestampTotalAssets;

    /* IMMUTABLES */

    /// @dev Network middleware service used to authorize slashes.
    address internal immutable NETWORK_MIDDLEWARE_SERVICE;

    /* STATE VARIABLES */

    /// @inheritdoc IAppAdapter
    bytes32 public subnetwork;
    /// @inheritdoc IAppAdapter
    address public operator;
    /// @inheritdoc IAppAdapter
    uint48 public duration;

    /* CONSTRUCTOR */

    constructor(address vaultFactory, address adapterFactory, address curatorRegistry, address networkMiddlewareService)
        Adapter(vaultFactory, adapterFactory, curatorRegistry)
    {
        NETWORK_MIDDLEWARE_SERVICE = networkMiddlewareService;
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc IAdapter
    function deallocatable() public view returns (uint256) {
        return totalAssets().saturatingSub(slashable());
    }

    /// @inheritdoc IAdapter
    function totalAssets() public view override(Adapter, IAdapter) returns (uint256) {
        return _timestampTotalAssets.latest();
    }

    /// @inheritdoc IAppAdapter
    function stake() public view returns (uint256) {
        return _stakeAt(uint48(block.timestamp));
    }

    /// @inheritdoc IAppAdapter
    function slashable() public view returns (uint256) {
        return _slashableAt(uint48(block.timestamp));
    }

    /// @inheritdoc IAppAdapter
    function stakeAt(uint48, bytes calldata) public view returns (uint256) {
        return _stakeAt(uint48(block.timestamp));
    }

    /// @inheritdoc IAppAdapter
    function slashableAt(uint48, bytes calldata) public view returns (uint256) {
        return _slashableAt(uint48(block.timestamp));
    }

    /// @dev Returns slashable stake at a timestamp.
    function _slashableAt(uint48 timestamp) internal view returns (uint256) {
        if (_stakes.length == 0) {
            return 0;
        }
        Stake storage curStake = _stakes[_timestampToStake.upperLookupRecent(timestamp)];
        return curStake.initialStake.saturatingSub(curStake.slashed.upperLookupRecent(timestamp))
            .saturatingSub(curStake.debt.upperLookupRecent(timestamp));
    }

    /// @dev Returns guaranteed stake at a timestamp.
    function _stakeAt(uint48 timestamp) internal view returns (uint256) {
        if (_stakes.length == 0) {
            return 0;
        }
        Stake storage curStake = _stakes[_timestampToStake.upperLookupRecent(timestamp)];
        return curStake.initialStake.saturatingSub(curStake.slashed.upperLookupRecent(timestamp))
            .saturatingSub(curStake.debt.upperLookupRecent(timestamp + duration));
    }

    /* PUBLIC FUNCTIONS (NETWORK) */

    /// @inheritdoc IAppAdapter
    function slash(uint256 amount) public returns (uint256 slashedAmount) {
        if (INetworkMiddlewareService(NETWORK_MIDDLEWARE_SERVICE).middleware(subnetwork.network()) != msg.sender) {
            revert NotNetworkMiddleware();
        }

        slashedAmount = Math.min(amount, slashable());
        if (slashedAmount == 0) {
            revert InsufficientSlash();
        }

        address burner = IVaultV2(vault).burner();
        if (burner == address(0)) {
            revert NoBurner();
        }

        Stake storage curStake = _stakes[_timestampToStake.latest()];
        curStake.slashed.push(uint48(block.timestamp), curStake.slashed.latest() + slashedAmount);

        _timestampTotalAssets.push(uint48(block.timestamp), _timestampTotalAssets.latest() - slashedAmount);

        // Send slashed collateral to the vault burner.
        IERC20(IVaultV2(vault).asset()).safeTransfer(burner, slashedAmount);

        emit Slash(slashedAmount);
    }

    /* PUBLIC FUNCTIONS (INTERNAL) */

    /// @dev Deallocates assets that are not slashable.
    function _deallocate(uint256 amount) internal override returns (uint256 deallocated) {
        uint256 curTotalAssets = _timestampTotalAssets.latest();
        if (curTotalAssets == 0) {
            return 0;
        }

        deallocated = Math.min(amount, curTotalAssets.saturatingSub(slashable()));
        if (deallocated != 0) {
            _timestampTotalAssets.push(uint48(block.timestamp), curTotalAssets.saturatingSub(deallocated));
        }
    }

    /// @dev Requests delayed deallocation debt accounting.
    function _requestDeallocate(uint256 amount) internal override {
        uint256 curSlashable = slashable();

        // it means the debt was somehow reduced and we can reset stake/debt/slashed
        if (
            IUniversalDelegator(IVaultV2(vault).delegator()).limitOf(address(this)).saturatingSub(amount)
                >= curSlashable
        ) {
            Stake storage newStake = _stakes.push();
            newStake.initialStake = curSlashable;
            _timestampToStake.push(uint48(block.timestamp), uint208(_stakes.length - 1));
        } else {
            Stake storage curStake = _stakes[_timestampToStake.latest()];
            // if debt is increased we keep increasing it
            if (curStake.debt.latest() < amount) {
                curStake.debt.push(uint48(block.timestamp), amount);
            }
            // if debt is decreased but still cannot release assets then we don't do anything
        }
    }

    function _allocate(uint256 amount) internal override returns (uint256) {
        if (amount == 0) {
            return 0;
        }

        uint256 curTotalAssets = _timestampTotalAssets.latest() + amount;
        _timestampTotalAssets.push(uint48(block.timestamp), curTotalAssets);
        Stake storage newStake = _stakes.push();
        newStake.initialStake = curTotalAssets;
        _timestampToStake.push(uint48(block.timestamp), uint208(_stakes.length - 1));

        return amount;
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Initializes the configured network-operator pair.
    function __initialize(address, bytes memory data) internal override {
        InitParams memory params = abi.decode(data, (InitParams));
        if (params.subnetwork == bytes32(0) || params.operator == address(0)) {
            revert InvalidNetOrOp();
        }
        if (params.duration == 0) {
            revert InvalidDuration();
        }
        subnetwork = params.subnetwork;
        operator = params.operator;
        duration = params.duration;

        emit Initialize(params);
    }
}
