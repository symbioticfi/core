// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {AppAdapter} from "./AppAdapter.sol";
import {CoWSwapConverter} from "./common/CoWSwapConverter.sol";

import {Subnetwork} from "../libraries/Subnetwork.sol";

import {IAdapter} from "../../interfaces/adapters/IAdapter.sol";
import {IAppAdapter} from "../../interfaces/adapters/IAppAdapter.sol";
import {IConverter} from "../../interfaces/adapters/common/IConverter.sol";
import {INetworkMiddlewareService} from "../../interfaces/service/INetworkMiddlewareService.sol";
import {IRegistry} from "../../interfaces/common/IRegistry.sol";
import {IRestakingAppAdapter, MAX_DEPTH} from "../../interfaces/adapters/IRestakingAppAdapter.sol";
import {IUniversalDelegator, MAX_SHARE} from "../../interfaces/delegator/IUniversalDelegator.sol";
import {IVaultV2} from "../../interfaces/vault/IVaultV2.sol";
import {IWithdrawalQueue} from "../../interfaces/vault/IWithdrawalQueue.sol";

import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
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
    address[] public underlyingVaults;

    struct WithdrawalRequests {
        uint256 firstUnclaimed;
        uint64[] tokenIds;
    }

    mapping(address vault => WithdrawalRequests) public withdrawalRequests;

    /* CONSTRUCTOR */

    constructor(
        address vaultFactory,
        address adapterFactory,
        address curatorRegistry,
        address networkMiddlewareService,
        address cowSwapSettlement,
        address cowSwapVaultRelayer,
        uint32 maxValidToDuration
    )
        AppAdapter(
            vaultFactory,
            adapterFactory,
            curatorRegistry,
            networkMiddlewareService,
            cowSwapSettlement,
            cowSwapVaultRelayer,
            maxValidToDuration
        )
    {}

    /* VIEW FUNCTIONS */

    /// @inheritdoc IAdapter
    function freeAssets() public view override(AppAdapter, IAdapter) returns (uint256) {
        return totalAssets() - super.slashable();
    }

    /// @inheritdoc IAdapter
    function totalAssets() public view override(AppAdapter, IAdapter) returns (uint256) {
        return IERC20(IERC4626(vault).asset()).balanceOf(address(this));
    }

    /// @inheritdoc IAppAdapter
    function slashable() public view override(AppAdapter, IAppAdapter) returns (uint256) {
        return _convertToAsset(super.slashable());
    }

    /// @inheritdoc IAppAdapter
    function stake() public view override(AppAdapter, IAppAdapter) returns (uint256) {
        return _convertToAsset(super.stake());
    }

    /// @inheritdoc IAppAdapter
    function stakeAt(uint48 timestamp) public view override(AppAdapter, IAppAdapter) returns (uint256) {
        if (asset != IERC4626(vault).asset()) {
            revert InvalidAsset();
        }
        return _convertToAsset(super.stakeAt(timestamp));
    }

    /* PUBLIC FUNCTIONS (PERMISSIONLESS) */

    /// @inheritdoc IAppAdapter
    function reward(address token, uint256 amount) public override(AppAdapter, IAppAdapter) {
        super.reward(token, amount);
        for (uint256 i = underlyingVaults.length; i > 0; --i) {
            token = underlyingVaults[i - 1];
            amount = IERC4626(token).deposit(amount, address(this));
        }
    }

    /// @inheritdoc IRestakingAppAdapter
    function syncSlash() public {
        uint256 amount;
        for (uint256 i; i < underlyingVaults.length; ++i) {
            address withdrawalQueue = IVaultV2(underlyingVaults[i]).withdrawalQueue();

            // Create a request for previously claimed vault shares.
            if (amount > 0) {
                withdrawalRequests[underlyingVaults[i]].tokenIds
                    .push(uint64(IWithdrawalQueue(withdrawalQueue).requestRedeem(amount, address(this))));
                amount = 0;
            }
            // Try claim existing requests greedily.
            WithdrawalRequests storage requests = withdrawalRequests[underlyingVaults[i]];
            uint256 indexToClaim = requests.firstUnclaimed;
            for (; indexToClaim < requests.tokenIds.length; ++indexToClaim) {
                uint256 tokenId = requests.tokenIds[indexToClaim];
                try IWithdrawalQueue(withdrawalQueue).claim(tokenId) returns (uint256 assets, uint256) {
                    amount += assets;
                } catch {}
                // Stop if the last request was not fully claimed.
                if (!IWithdrawalQueue(withdrawalQueue).isClaimed(tokenId)) {
                    break;
                }
            }
            requests.firstUnclaimed = indexToClaim;
        }
        // Send `asset` obtained from the last vault to the burner.
        if (amount > 0) {
            super._sendToBurner(amount);
        }
    }

    /* PUBLIC FUNCTIONS (NETWORK) */

    /// @inheritdoc IAppAdapter
    function slash(uint256 amount) public override(AppAdapter, IAppAdapter) returns (uint256) {
        return super.slash(_convertToShare(amount));
    }

    /* INITIALIZATION */

    /// @dev Initializes the configured base asset and network-operator pair.
    function __initialize(address initVault, bytes memory data) internal override {
        RestakingInitParams memory params = abi.decode(data, (RestakingInitParams));

        super.__initialize(initVault, abi.encode(params.initParams));

        asset = params.asset;

        address curAsset = IERC4626(vault).asset();
        for (uint256 depth; curAsset != params.asset && depth < MAX_DEPTH; ++depth) {
            if (!IRegistry(VAULT_FACTORY).isEntity(curAsset)) {
                revert InvalidBaseAsset();
            }
            underlyingVaults.push(curAsset);
            IERC20(curAsset).forceApprove(IVaultV2(curAsset).withdrawalQueue(), type(uint256).max);
            IERC20(IERC4626(curAsset).asset()).forceApprove(curAsset, type(uint256).max);
            curAsset = IERC4626(curAsset).asset();
        }
        if (curAsset != params.asset) {
            revert InvalidAsset();
        }
        if (underlyingVaults.length > 0) {
            IERC20(curAsset).forceApprove(underlyingVaults[underlyingVaults.length - 1], type(uint256).max);
        }
    }

    /* INTERNAL FUNCTIONS */

    function _sendToBurner(uint256 amount) internal override {
        for (uint256 i; i < underlyingVaults.length; ++i) {
            address withdrawalQueue = IVaultV2(underlyingVaults[i]).withdrawalQueue();
            uint256 tokenId = IWithdrawalQueue(withdrawalQueue).requestRedeem(amount, address(this));
            try IWithdrawalQueue(withdrawalQueue).claim(tokenId) returns (uint256 curAmount, uint256 shares) {
                if (shares < amount) {
                    withdrawalRequests[underlyingVaults[i]].tokenIds.push(uint64(tokenId));
                }
                amount = curAmount;
            } catch {
                withdrawalRequests[underlyingVaults[i]].tokenIds.push(uint64(tokenId));
                amount = 0;
            }
            if (amount == 0) {
                return;
            }
        }
        super._sendToBurner(amount);
    }

    /// @dev Converts current vault-asset shares into the configured base asset with previewRedeem.
    function _convertToAsset(uint256 amount) internal view returns (uint256) {
        for (uint256 i; i < underlyingVaults.length; ++i) {
            amount = IERC4626(underlyingVaults[i]).previewRedeem(amount);
        }
        return amount;
    }

    /// @dev Converts the configured base asset into current vault-asset shares with previewDeposit.
    function _convertToShare(uint256 amount) internal view returns (uint256) {
        for (uint256 i = underlyingVaults.length; i > 0; --i) {
            amount = IERC4626(underlyingVaults[i - 1]).previewDeposit(amount);
        }
        return amount;
    }
}
