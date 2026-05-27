// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {AppAdapter} from "./AppAdapter.sol";

import {Subnetwork} from "../libraries/Subnetwork.sol";

import {IAdapter} from "../../interfaces/adapters/IAdapter.sol";
import {IAppAdapter, BURNER_GAS_LIMIT, BURNER_RESERVE} from "../../interfaces/adapters/IAppAdapter.sol";
import {IRestakingAppAdapter} from "../../interfaces/adapters/IRestakingAppAdapter.sol";
import {IBurner} from "../../interfaces/slasher/IBurner.sol";
import {INetworkMiddlewareService} from "../../interfaces/service/INetworkMiddlewareService.sol";
import {IUniversalDelegator} from "../../interfaces/delegator/IUniversalDelegator.sol";
import {IVaultV2} from "../../interfaces/vault/IVaultV2.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title RestakingAppAdapter
/// @notice App adapter for ERC4626 restaking-token vault assets with base-asset rewards and slashing.
contract RestakingAppAdapter is AppAdapter, IRestakingAppAdapter {
    using Checkpoints for Checkpoints.Trace256;
    using Checkpoints for Checkpoints.Trace208;
    using Subnetwork for bytes32;
    using SafeERC20 for IERC20;
    using Math for uint256;

    /* STATE VARIABLES */

    /// @inheritdoc IRestakingAppAdapter
    address public baseAsset;

    /* CONSTRUCTOR */

    constructor(address vaultFactory, address adapterFactory, address curatorRegistry, address networkMiddlewareService)
        AppAdapter(vaultFactory, adapterFactory, curatorRegistry, networkMiddlewareService)
    {}

    /* VIEW FUNCTIONS */

    /// @inheritdoc IAdapter
    function deallocatable() public view override(AppAdapter, IAdapter) returns (uint256) {
        return totalAssets().saturatingSub(_slashableShares());
    }

    /// @inheritdoc IAppAdapter
    function slashable() public view override(AppAdapter, IAppAdapter) returns (uint256) {
        return IERC4626(IERC4626(vault).asset()).previewRedeem(_slashableShares());
    }

    /// @inheritdoc IAppAdapter
    function stake() public view override(AppAdapter, IAppAdapter) returns (uint256) {
        Stake storage curStake = _stakes[_stakePos.latest()];
        uint256 stakeShares = curStake.initialStake.saturatingSub(curStake.slashed.latest())
            .saturatingSub(curStake.debt.upperLookupRecent(uint48(block.timestamp) + duration - 1));
        return IERC4626(IERC4626(vault).asset()).previewRedeem(stakeShares);
    }

    /// @inheritdoc IAppAdapter
    function stakeAt(uint48 timestamp) public view override(AppAdapter, IAppAdapter) returns (uint256) {
        Stake storage curStake = _stakes[_stakePos.upperLookupRecent(timestamp)];
        uint256 stakeShares = curStake.initialStake.saturatingSub(curStake.slashed.upperLookupRecent(timestamp))
            .saturatingSub(curStake.debt.upperLookupRecent(uint48(timestamp) + duration - 1));
        return IERC4626(IERC4626(vault).asset()).previewRedeem(stakeShares);
    }

    /* PUBLIC FUNCTIONS (PERMISSIONLESS) */

    /// @inheritdoc IAppAdapter
    function reward(uint256 amount) public override(AppAdapter, IAppAdapter) {
        IERC20(baseAsset).safeTransferFrom(msg.sender, address(this), amount);
        address restakingToken = IERC4626(vault).asset();
        if (IERC20(baseAsset).allowance(address(this), restakingToken) < amount) {
            IERC20(baseAsset).forceApprove(restakingToken, type(uint256).max);
        }
        IERC4626(restakingToken).deposit(amount, vault);
    }

    /* PUBLIC FUNCTIONS (NETWORK) */

    /// @inheritdoc IAppAdapter
    function slash(uint256 amount) public override(AppAdapter, IAppAdapter) returns (uint256) {
        if (INetworkMiddlewareService(NETWORK_MIDDLEWARE_SERVICE).middleware(subnetwork.network()) != msg.sender) {
            revert NotNetworkMiddleware();
        }

        uint256 slashableShares = _slashableShares();
        amount = Math.min(amount, IERC4626(IERC4626(vault).asset()).previewRedeem(slashableShares));
        if (amount == 0) {
            revert InsufficientSlash();
        }

        Stake storage curStake = _stakes[_stakePos.latest()];
        uint256 slashedShares = IERC4626(IERC4626(vault).asset()).withdraw(amount, burner, address(this));
        curStake.slashed.push(uint48(block.timestamp), curStake.slashed.latest() + slashedShares);

        // Decrease the adapter limits to avoid new allocations.
        IUniversalDelegator(IVaultV2(vault).delegator()).decreaseLimits(slashedShares, 0);

        bytes memory burnerCalldata = abi.encodeCall(IBurner.onSlash, (subnetwork, operator, amount, 0));
        if (gasleft() < BURNER_RESERVE + BURNER_GAS_LIMIT * 64 / 63) {
            revert InsufficientBurnerGas();
        }
        address curBurner = burner;
        assembly ("memory-safe") {
            pop(call(BURNER_GAS_LIMIT, curBurner, 0, add(burnerCalldata, 0x20), mload(burnerCalldata), 0, 0))
        }

        emit Slash(amount);
        return amount;
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Requests delayed deallocation debt accounting in vault-asset shares.
    function _requestDeallocate(uint256 amount) internal override {
        uint256 curSlashable = _slashableShares();

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
            // Keep existing debt when the request shrinks but cannot release assets yet.
        }
    }

    /// @dev Initializes the configured base asset and network-operator pair.
    function __initialize(address initVault, bytes memory data) internal override {
        RestakingInitParams memory params = abi.decode(data, (RestakingInitParams));
        address restakingToken = IERC4626(initVault).asset();
        if (params.baseAsset == address(0) || IERC4626(restakingToken).asset() != params.baseAsset) {
            revert InvalidBaseAsset();
        }

        baseAsset = params.baseAsset;

        super.__initialize(
            initVault,
            abi.encode(
                IAppAdapter.InitParams({
                    subnetwork: params.subnetwork,
                    operator: params.operator,
                    duration: params.duration,
                    burner: params.burner
                })
            )
        );
    }

    /* INTERNAL VIEW FUNCTIONS */

    /// @dev Returns the current slashable amount in vault-asset shares.
    function _slashableShares() internal view returns (uint256) {
        Stake storage curStake = _stakes[_stakePos.latest()];
        return curStake.initialStake.saturatingSub(curStake.slashed.latest())
            .saturatingSub(curStake.debt.upperLookupRecent(block.timestamp));
    }
}
