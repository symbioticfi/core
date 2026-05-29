// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Adapter} from "./Adapter.sol";

import {Subnetwork} from "../libraries/Subnetwork.sol";

import {IAdapter} from "../../interfaces/adapters/IAdapter.sol";
import {IAppAdapter, BURNER_GAS_LIMIT, BURNER_RESERVE} from "../../interfaces/adapters/IAppAdapter.sol";
import {IBurner} from "../../interfaces/slasher/IBurner.sol";
import {INetworkMiddlewareService} from "../../interfaces/service/INetworkMiddlewareService.sol";
import {IUniversalDelegator} from "../../interfaces/delegator/IUniversalDelegator.sol";
import {IVaultV2} from "../../interfaces/vault/IVaultV2.sol";
import {MAX_SHARE} from "../../interfaces/delegator/IUniversalDelegator.sol";

import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title AppAdapter
/// @notice Single network-operator guarantee adapter.
contract AppAdapter is Adapter, IAppAdapter {
    using Checkpoints for Checkpoints.Trace256;
    using Checkpoints for Checkpoints.Trace208;
    using Subnetwork for bytes32;
    using SafeERC20 for IERC20;
    using Math for uint256;

    /* IMMUTABLES */

    /// @dev Network middleware service used to authorize slashes.
    address internal immutable NETWORK_MIDDLEWARE_SERVICE;

    /* STATE VARIABLES */

    /// @inheritdoc IAppAdapter
    address public burner;
    /// @inheritdoc IAppAdapter
    uint48 public duration;
    /// @inheritdoc IAppAdapter
    address public operator;
    /// @inheritdoc IAppAdapter
    bytes32 public subnetwork;
    /// @inheritdoc IAppAdapter
    address public asset;

    /// @dev Stakes for the configured pair.
    Stake[] internal _stakes;
    /// @dev Position of the current stake in the _stakes array.
    Checkpoints.Trace208 internal _stakePos;

    /* CONSTRUCTOR */

    constructor(address vaultFactory, address adapterFactory, address networkMiddlewareService)
        Adapter(vaultFactory, adapterFactory)
    {
        NETWORK_MIDDLEWARE_SERVICE = networkMiddlewareService;
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc IAdapter
    function freeAssets() public view virtual override(Adapter, IAdapter) returns (uint256) {
        return totalAssets() - slashable();
    }

    /// @inheritdoc IAdapter
    function totalAssets() public view virtual override(Adapter, IAdapter) returns (uint256) {
        return IERC20(asset).balanceOf(address(this));
    }

    /// @inheritdoc IAppAdapter
    function slashable() public view virtual returns (uint256) {
        return _slashable();
    }

    /// @dev Computes the slashable stake for the current stake.
    function _slashable() internal view returns (uint256) {
        Stake storage curStake = _stakes[_stakePos.latest()];
        return curStake.initialStake.saturatingSub(curStake.slashed.latest())
            .saturatingSub(curStake.debt.upperLookupRecent(block.timestamp));
    }

    /// @inheritdoc IAppAdapter
    function stake() public view virtual returns (uint256) {
        Stake storage curStake = _stakes[_stakePos.latest()];
        return curStake.initialStake.saturatingSub(curStake.slashed.latest())
            .saturatingSub(curStake.debt.upperLookupRecent(uint48(block.timestamp) + duration - 1));
    }

    /// @inheritdoc IAppAdapter
    function stakeAt(uint48 timestamp) public view virtual returns (uint256) {
        Stake storage curStake = _stakes[_stakePos.upperLookupRecent(timestamp)];
        return curStake.initialStake.saturatingSub(curStake.slashed.upperLookupRecent(timestamp))
            .saturatingSub(curStake.debt.upperLookupRecent(uint48(timestamp) + duration - 1));
    }

    /* PUBLIC FUNCTIONS (NETWORK) */

    /// @inheritdoc IAppAdapter
    function slash(uint256 amount) public virtual returns (uint256) {
        if (INetworkMiddlewareService(NETWORK_MIDDLEWARE_SERVICE).middleware(subnetwork.network()) != msg.sender) {
            revert NotNetworkMiddleware();
        }

        amount = Math.min(amount, _slashable());
        if (amount == 0) {
            revert InsufficientSlash();
        }

        Stake storage curStake = _stakes[_stakePos.latest()];
        curStake.slashed.push(uint48(block.timestamp), curStake.slashed.latest() + amount);

        // Decrease the adapter limits to avoid new allocations.
        IUniversalDelegator(IVaultV2(vault).delegator()).decreaseLimits(amount, 0);

        // Send slashed amount to the burner.
        _sendToBurner(amount);

        emit Slash(amount);
        return amount;
    }

    /// @inheritdoc IAppAdapter
    function release() public virtual {
        if (
            subnetwork.network() != msg.sender
                && INetworkMiddlewareService(NETWORK_MIDDLEWARE_SERVICE).middleware(subnetwork.network()) != msg.sender
        ) {
            revert NotNetworkOrMiddleware();
        }

        _stakePos.push(uint48(block.timestamp), uint208(_stakes.length));
        _stakes.push();
        IUniversalDelegator(IVaultV2(vault).delegator()).decreaseLimits(type(uint256).max, MAX_SHARE);

        emit Release();
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Allocates an amount into a fresh stake checkpoint.
    function _allocate(uint256 amount) internal override returns (uint256) {
        if (amount == 0) {
            return 0;
        }

        _stakePos.push(uint48(block.timestamp), uint208(_stakes.length));
        _stakes.push().initialStake = totalAssets();

        return amount;
    }

    /// @dev Deallocates an amount that is not slashable.
    function _deallocate(uint256) internal pure override returns (uint256) {
        return 0;
    }

    /// @dev Requests delayed deallocation debt accounting.
    function _requestDeallocate(uint256 amount) internal virtual override {
        uint256 curSlashable = _slashable();

        // Reset stake, debt, and slashed when the debt was reduced enough.
        if (
            Math.min(IUniversalDelegator(IVaultV2(vault).delegator()).limitOf(address(this)), totalAssets())
                    .saturatingSub(amount) >= curSlashable
        ) {
            _stakePos.push(uint48(block.timestamp), uint208(_stakes.length));
            _stakes.push().initialStake = curSlashable;
        } else {
            Stake storage curStake = _stakes[_stakePos.latest()];
            // Keep increasing debt when the request grows.
            if (curStake.debt.latest() < amount) {
                curStake.debt.push(uint48(block.timestamp) + duration, amount);
            }
            // Keep existing debt when the request shrinks but cannot release the amount yet.
        }
    }

    /// @dev Sends slashed amount to the burner and invokes its hook.
    function _sendToBurner(uint256 amount) internal virtual {
        address curBurner = burner;
        IERC20(asset).safeTransfer(curBurner, amount);
        bytes memory burnerCalldata = abi.encodeCall(IBurner.onSlash, (subnetwork, operator, amount, 0));
        if (gasleft() < BURNER_RESERVE + BURNER_GAS_LIMIT * 64 / 63) {
            revert InsufficientBurnerGas();
        }
        assembly ("memory-safe") {
            pop(call(BURNER_GAS_LIMIT, curBurner, 0, add(burnerCalldata, 0x20), mload(burnerCalldata), 0, 0))
        }
    }

    /// @dev Initializes the configured network-operator pair.
    function __initialize(address, bytes memory data) internal virtual override {
        InitParams memory params = abi.decode(data, (InitParams));

        asset = IERC4626(vault).asset();

        if (params.subnetwork == bytes32(0) || params.operator == address(0)) {
            revert InvalidNetOrOp();
        }
        if (params.duration == 0) {
            revert InvalidDuration();
        }
        if (params.burner == address(0)) {
            revert NoBurner();
        }

        burner = params.burner;
        duration = params.duration;
        operator = params.operator;
        subnetwork = params.subnetwork;

        _stakes.push();

        emit Initialize(params);
    }
}
