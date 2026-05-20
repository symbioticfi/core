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
    function stakeAt(uint48 timestamp, bytes calldata) public view returns (uint256) {
        return _stakeAt(uint48(block.timestamp));
    }

    function slashableAt(uint48 timestamp, bytes calldata) public view returns (uint256) {
        return _slashableAt(uint48(block.timestamp));
    }

    /// @inheritdoc IAppAdapter
    function _slashableAt(uint48 timestamp) internal view returns (uint256) {
        Stake storage curStake = _stakes[_timestampToStake.upperLookupRecent(timestamp)];
        return curStake.initialStake.saturatingSub(curStake.slashed.at(timestamp)).saturatingSub(curStake.debt.at(timestamp));
    }

    /// @inheritdoc IAppAdapter
    function _stakeAt(uint48 timestamp) internal view returns (uint256) {
        Stake storage curStake = _stakes[_timestampToStake.upperLookupRecent(timestamp)];
        return curStake.initialStake.saturatingSub(curStake.slashed.at(timestamp)).saturatingSub(curStake.debt.at(timestamp + duration));
    }

    /* PUBLIC FUNCTIONS (NETWORK) */

    /// @inheritdoc IAppAdapter
    function slash(bytes32 subnetwork_, address operator_, uint256 amount, uint48 captureTimestamp, bytes calldata data)
        public
        returns (uint256 slashedAmount)
    {
        _checkNetworkMiddleware(subnetwork_);

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

        // idk what is this
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

        uint256 curTotalAssets = _timestampTotalAssets.latest();
        if (curTotalAssets == 0) {
            return (0, 0);
        }

        deallocated = Math.min(amount, curTotalAssets.saturatingSub(slashable()));
        if (deallocated != 0) {
            _timestampTotalAssets.push(uint48(block.timestamp), curTotalAssets.saturatingSub(deallocated));
        }

        // TODO: idk wtf is this
        pending = 0;
    }

    function onDebt(uint256 amount) public {
        if (IVaultV2(vault).delegator() != msg.sender) {
            revert NotVault();
        }

        uint256 curTotalAssets = totalAssets();
        uint256 curSlashable = slashable();

        // it means the debt was somehow reduced and we can reset stake/debt/slashed
        if (curTotalAssets - amount >= curSlashable) {
            Stake storage newStake = _stakes.push();
            newStake.initialStake = curSlashable;
            _timestampToStake.push(uint48(block.timestamp), uint208(_stakes.length - 1));
        }
        else {
            Stake storage curStake = _stakes[_timestampToStake.latest()];
            // if debt is increased we keep increasing it
            if (curStake.debt.latest() < amount) {
                curStake.debt.push(uint48(block.timestamp), amount);
            }
            // if debt is decreased but still cannot release assets then we don't do anything
        }
    }

    function _allocate(uint256 amount) 
        internal
        virtual
        returns (uint256)
    {
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
        if (params.isBurnerHook && IVaultV2(vault).burner() == address(0)) {
            revert NoBurner();
        }

        subnetwork = params.subnetwork;
        operator = params.operator;
        duration = params.duration;

        emit Initialize(params);
    }

    /// @dev Reverts unless the caller is the network middleware for the subnetwork.
    function _checkNetworkMiddleware(bytes32 subnetwork_) internal view {
        if (INetworkMiddlewareService(NETWORK_MIDDLEWARE_SERVICE).middleware(subnetwork_.network()) != msg.sender) {
            revert NotNetworkMiddleware();
        }
    }

    /// @dev Calls the burner hook after a slash when hook mode is enabled.
    function _burnerOnSlash(bytes32 subnetwork_, address operator_, uint256 amount, uint48 captureTimestamp) internal {
            address burner = IVaultV2(vault).burner();
            bytes memory burnerCalldata =
                abi.encodeCall(IBurner.onSlash, (subnetwork_, operator_, amount, captureTimestamp));

            assembly ("memory-safe") {
                pop(call(gas(), burner, 0, add(burnerCalldata, 0x20), mload(burnerCalldata), 0, 0))
            }
    }
}
