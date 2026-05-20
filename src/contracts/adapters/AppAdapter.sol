// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Adapter} from "./Adapter.sol";

import {Subnetwork} from "../libraries/Subnetwork.sol";

import {IAdapter} from "../../interfaces/adapters/IAdapter.sol";
import {IAppAdapter} from "../../interfaces/adapters/IAppAdapter.sol";
import {IUniversalDelegator} from "../../interfaces/delegator/IUniversalDelegator.sol";
import {IBurner} from "../../interfaces/slasher/IBurner.sol";
import {INetworkMiddlewareService} from "../../interfaces/service/INetworkMiddlewareService.sol";
import {IVaultV2} from "../../interfaces/vault/IVaultV2.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title AppAdapter
/// @notice Single network-operator guarantee adapter.
contract AppAdapter is Adapter, IAppAdapter {
    using Math for uint256;
    using SafeERC20 for IERC20;
    using Subnetwork for bytes32;
    using Checkpoints for Checkpoints.Trace256;

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

    /// @dev Checkpointed stake for the configured pair.
    Checkpoints.Trace256 internal _stake;

    /* CONSTRUCTOR */

    constructor(address vaultFactory, address adapterFactory, address curatorRegistry, address networkMiddlewareService)
        Adapter(vaultFactory, adapterFactory, curatorRegistry)
    {
        NETWORK_MIDDLEWARE_SERVICE = networkMiddlewareService;
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc IAdapter
    function deallocatable() public view returns (uint256) {
        uint256 locked = _stake.latest();
        if (_pendingAssets != 0 && _pendingAt > block.timestamp) {
            locked += _pendingAssets;
        }
        return totalAssets().saturatingSub(locked);
    }

    /// @inheritdoc IAdapter
    function totalAssets() public view override(Adapter, IAdapter) returns (uint256) {
        address curVault = vault;
        if (curVault == address(0)) {
            return 0;
        }
        return IERC20(IVaultV2(curVault).asset()).balanceOf(address(this));
    }

    /// @inheritdoc IAppAdapter
    function stake() public view returns (uint256) {
        return _stake.latest();
    }

    /// @inheritdoc IAppAdapter
    function stakeAt(uint48 timestamp, bytes calldata) public view returns (uint256) {
        return _stake.upperLookupRecent(_checkpointTimestamp(timestamp));
    }

    /* PUBLIC FUNCTIONS (NETWORK) */

    /// @inheritdoc IAppAdapter
    function slash(bytes32 subnetwork_, address operator_, uint256 amount, uint48 captureTimestamp, bytes calldata data)
        public
        returns (uint256 slashedAmount)
    {
        _checkNetworkMiddleware(subnetwork_);

        slashedAmount = Math.min(amount, _slashableStake(subnetwork_, operator_, captureTimestamp, data));
        if (slashedAmount == 0) {
            revert InsufficientSlash();
        }

        address burner = IVaultV2(vault).burner();
        if (burner == address(0)) {
            revert NoBurner();
        }

        slashed += slashedAmount;
        slashedAt = uint48(block.timestamp);
        uint256 pendingSlashed = Math.min(slashedAmount, _pendingAssets);
        if (pendingSlashed != 0) {
            _pendingAssets -= pendingSlashed;
            if (_pendingAssets == 0) {
                _pendingAt = 0;
            }
        }
        _decreaseStake(slashedAmount - pendingSlashed);

        IERC20(IVaultV2(vault).asset()).safeTransfer(burner, slashedAmount);
        IUniversalDelegator(IVaultV2(vault).delegator()).onAdapterSlash(slashedAmount);
        _burnerOnSlash(subnetwork_, operator_, slashedAmount, captureTimestamp);

        emit Slash(subnetwork_, operator_, slashedAmount);
    }

    /* PUBLIC FUNCTIONS (INTERNAL) */

    /// @inheritdoc IAdapter
    function deallocate(uint256 amount)
        public
        override(Adapter, IAdapter)
        returns (uint256 deallocated, uint256 pending)
    {
        if (IVaultV2(vault).delegator() != msg.sender) {
            revert NotVault();
        }

        if (_isRecover) {
            address asset = IVaultV2(vault).asset();
            if (IERC20(asset).allowance(address(this), vault) < amount) {
                IERC20(asset).forceApprove(vault, type(uint256).max);
            }
            return (amount, 0);
        }

        deallocated = Math.min(amount, deallocatable());
        if (deallocated != 0) {
            _settlePendingDecrease(deallocated);

            address asset = IVaultV2(vault).asset();
            if (IERC20(asset).allowance(address(this), vault) < deallocated) {
                IERC20(asset).forceApprove(vault, type(uint256).max);
            }
        }

        uint256 remaining = amount - deallocated;
        if (remaining != 0) {
            pending = _requestPendingDeallocation(remaining);
        }
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Skims no assets; this adapter does not produce external yield.
    function _skim() internal pure override returns (uint256) {
        return 0;
    }

    /// @dev Keeps allocated asset liquid inside the adapter and records it as stake.
    function _allocate(uint256 amount) internal override returns (uint256) {
        _increaseStake(amount);
        return amount;
    }

    /// @dev Returns currently free asset from the adapter.
    function _deallocate(uint256 amount) internal override returns (uint256 deallocated) {
        deallocated = Math.min(amount, deallocatable());
        if (deallocated != 0) {
            _settlePendingDecrease(deallocated);

            address asset = IVaultV2(vault).asset();
            if (IERC20(asset).allowance(address(this), vault) < deallocated) {
                IERC20(asset).forceApprove(vault, type(uint256).max);
            }
        }
    }

    /// @dev Initializes the configured network-operator pair.
    function __initialize(address, bytes memory data) internal override {
        InitParams memory params = abi.decode(data, (InitParams));
        if (params.subnetwork == bytes32(0) || params.operator == address(0)) {
            revert InvalidNetOrOp();
        }
        if (params.duration == 0) {
            revert InvalidDuration();
        }
        if (params.isBurnerHook && IVaultV2(vault).burner() == address(0)) {
            revert NoBurner();
        }

        subnetwork = params.subnetwork;
        operator = params.operator;
        duration = params.duration;
        isBurnerHook = params.isBurnerHook;

        emit Initialize(params);
    }

    /// @dev Registers a delayed deallocation decrease.
    function _requestPendingDeallocation(uint256 amount) internal returns (uint256 pending) {
        pending = Math.min(amount, _stake.latest());
        if (pending == 0) {
            return 0;
        }

        _pendingAssets += pending;
        _pendingAt = _checkpointTimestamp(uint48(block.timestamp));
        _decreaseStake(pending);
    }

    /// @dev Synchronizes adapter pending deallocation accounting.
    function _sync() internal override {
        uint256 closed = _pendingAssets;
        if (closed == 0) {
            return;
        }

        _pendingAssets = 0;
        _pendingAt = 0;
        _increaseStake(closed);
    }

    /// @dev Reduces unsettled delayed deallocation accounting after assets are returned to the vault.
    function _settlePendingDecrease(uint256 amount) internal {
        uint256 settled = Math.min(amount, _pendingAssets);
        if (settled == 0) {
            return;
        }

        _pendingAssets -= settled;
        if (_pendingAssets == 0) {
            _pendingAt = 0;
        }
    }

    /// @dev Returns slashable stake for a capture timestamp.
    function slashableStake() internal view returns (uint256) {
        uint256 timestamp = captureTimestamp == 0 ? block.timestamp : captureTimestamp;
        if (timestamp > block.timestamp || timestamp <= block.timestamp.saturatingSub(duration)) {
            return 0;
        }
        return Math.min(totalAssets(), stakeAt(uint48(timestamp)));
    }

    /// @dev Increases checkpointed stake.
    function _increaseStake(uint256 amount) internal {
        if (amount != 0) {
            _pushStake(_stake.latest() + amount);
        }
    }

    /// @dev Decreases checkpointed stake.
    function _decreaseStake(uint256 amount) internal {
        if (amount != 0) {
            _pushStake(_stake.latest().saturatingSub(amount));
        }
    }

    /// @dev Pushes a stake checkpoint at the current duration-shifted timestamp.
    function _pushStake(uint256 amount) internal {
        _stake.push(_checkpointTimestamp(uint48(block.timestamp)), amount);
    }

    /// @dev Returns the duration-shifted checkpoint timestamp.
    function _checkpointTimestamp(uint48 timestamp) internal view returns (uint48) {
        return uint48(Math.min(uint256(timestamp) + duration, uint256(type(uint48).max)));
    }

    /// @dev Reverts unless the caller is the network middleware for the subnetwork.
    function _checkNetworkMiddleware(bytes32 subnetwork_) internal view {
        if (INetworkMiddlewareService(NETWORK_MIDDLEWARE_SERVICE).middleware(subnetwork_.network()) != msg.sender) {
            revert NotNetworkMiddleware();
        }
    }

    /// @dev Calls the burner hook after a slash when hook mode is enabled.
    function _burnerOnSlash(bytes32 subnetwork_, address operator_, uint256 amount, uint48 captureTimestamp) internal {
        if (isBurnerHook) {
            address burner = IVaultV2(vault).burner();
            bytes memory burnerCalldata =
                abi.encodeCall(IBurner.onSlash, (subnetwork_, operator_, amount, captureTimestamp));

            assembly ("memory-safe") {
                pop(call(gas(), burner, 0, add(burnerCalldata, 0x20), mload(burnerCalldata), 0, 0))
            }
        }
    }
}
