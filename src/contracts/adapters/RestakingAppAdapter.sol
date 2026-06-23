// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {AppAdapter} from "./AppAdapter.sol";
import {CoWSwapConverter} from "./common/CoWSwapConverter.sol";

import {IAdapter} from "../../interfaces/adapters/IAdapter.sol";
import {IAppAdapter} from "../../interfaces/adapters/IAppAdapter.sol";
import {IConverter} from "../../interfaces/adapters/common/IConverter.sol";
import {IRegistry} from "../../interfaces/common/IRegistry.sol";
import {IRestakingAppAdapter, MAX_CLAIMS, MAX_DEPTH} from "../../interfaces/adapters/IRestakingAppAdapter.sol";
import {IVaultV2} from "../../interfaces/vault/IVaultV2.sol";
import {IWithdrawalQueue} from "../../interfaces/vault/IWithdrawalQueue.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title RestakingAppAdapter
/// @notice App adapter for ERC4626 restaking-token vault assets with base-asset rewards and slashing.
contract RestakingAppAdapter is AppAdapter, IRestakingAppAdapter {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /* STATE VARIABLES */

    /// @inheritdoc IRestakingAppAdapter
    address[] public underlyingVaults;

    /// @inheritdoc IRestakingAppAdapter
    mapping(address vault => WithdrawalRequests) public withdrawalRequests;

    /* CONSTRUCTOR */

    constructor(
        address vaultFactory,
        address adapterFactory,
        address cowSwapSettlement,
        address networkMiddlewareService
    ) AppAdapter(vaultFactory, adapterFactory, cowSwapSettlement, networkMiddlewareService) {}

    /* VIEW FUNCTIONS */

    /// @inheritdoc IAdapter
    function freeAssets() public view override(AppAdapter, IAdapter) returns (uint256) {
        return totalAssets() - super.slashable();
    }

    /// @inheritdoc IAdapter
    function totalAssets() public view override(AppAdapter, IAdapter) returns (uint256) {
        return IERC20(underlyingVaults[0]).balanceOf(address(this));
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
    function stakeAt(uint48) public pure override(AppAdapter, IAppAdapter) returns (uint256) {
        revert Unsupported();
    }

    /// @inheritdoc IRestakingAppAdapter
    function isUnsyncedSlash() public view returns (bool) {
        uint256 length = underlyingVaults.length;
        for (uint256 i; i < length; ++i) {
            WithdrawalRequests storage requests = withdrawalRequests[underlyingVaults[i]];
            if (requests.firstUnclaimed < requests.tokenIds.length) {
                return true;
            }
        }
        return false;
    }

    /* PUBLIC FUNCTIONS (PERMISSIONLESS) */

    /// @inheritdoc IConverter
    function convert(address tokenIn, uint256 amountIn, address tokenOut, bytes calldata data)
        public
        override(AppAdapter, IConverter)
    {
        uint256 length = underlyingVaults.length;
        for (uint256 i; i < length; ++i) {
            if (tokenIn == underlyingVaults[i]) {
                revert InvalidTokenIn();
            }
        }
        if (tokenIn == asset) {
            revert InvalidTokenIn();
        }
        if (tokenOut != asset) {
            revert InvalidTokenOut();
        }
        CoWSwapConverter.convert(tokenIn, amountIn, tokenOut, data);
    }

    /// @inheritdoc IAppAdapter
    function reward(address token, uint256 amount) public override(AppAdapter, IAppAdapter) {
        super.reward(token, amount);
        syncReward();
    }

    /// @dev Deposits held base assets through the underlying vault chain.
    function syncReward() public {
        uint256 length = underlyingVaults.length;
        for (uint256 i = length; i > 0; --i) {
            address vault = underlyingVaults[i - 1];
            address curAsset = i < length ? underlyingVaults[i] : asset;
            uint256 amount =
                Math.min(IERC20(curAsset).balanceOf(address(this)), IERC4626(vault).maxDeposit(address(this)));
            if (amount > 0) {
                IERC4626(vault).deposit(amount, address(this));
            }
        }
    }

    /// @inheritdoc IRestakingAppAdapter
    function syncSlash() public {
        uint256 amount;
        uint256 length = underlyingVaults.length;
        for (uint256 i; i < length; ++i) {
            address vault = underlyingVaults[i];
            address withdrawalQueue = IVaultV2(vault).withdrawalQueue();

            // Create a request for previously claimed vault shares.
            if (amount > 0) {
                withdrawalRequests[vault].tokenIds
                    .push(uint64(IWithdrawalQueue(withdrawalQueue).requestRedeem(amount, address(this))));
                amount = 0;
            }
            // Try claim existing requests greedily.
            WithdrawalRequests storage requests = withdrawalRequests[vault];
            uint256 indexToClaim = requests.firstUnclaimed;
            uint256 tokenIdsLength = requests.tokenIds.length;
            for (; indexToClaim < tokenIdsLength; ++indexToClaim) {
                uint256 tokenId = requests.tokenIds[indexToClaim];
                (uint256 requestShares, uint256 requestSharesClaimed,) =
                    IWithdrawalQueue(withdrawalQueue).requests(tokenId);
                (, uint256 shares) = IWithdrawalQueue(withdrawalQueue).claimable(tokenId);
                // Stop if claim amount is less than allowed per request, or it's the last claim until the request is fully claimed.
                if (shares < Math.min(requestShares.ceilDiv(MAX_CLAIMS), requestShares - requestSharesClaimed)) {
                    break;
                }
                try IWithdrawalQueue(withdrawalQueue).claim(tokenId, address(this)) returns (uint256 assets, uint256) {
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
    function slash(uint256 amount) public override(AppAdapter, IRestakingAppAdapter) {
        syncSlash();
        super.slash(_convertToShare(amount, true));
    }

    /// @inheritdoc IAppAdapter
    function release(uint256 amount) public override(AppAdapter, IAppAdapter) {
        syncSlash();
        super.release(_convertToShare(amount, false));
    }

    /* INTERNAL FUNCTIONS */

    /// @inheritdoc AppAdapter
    function _sendToBurner(uint256 amount) internal override {
        uint256 length = underlyingVaults.length;
        for (uint256 i; i < length; ++i) {
            address vault = underlyingVaults[i];
            address withdrawalQueue = IVaultV2(vault).withdrawalQueue();
            uint256 tokenId = IWithdrawalQueue(withdrawalQueue).requestRedeem(amount, address(this));
            try IWithdrawalQueue(withdrawalQueue).claim(tokenId, address(this)) returns (
                uint256 curAmount, uint256 shares
            ) {
                if (shares < amount) {
                    withdrawalRequests[vault].tokenIds.push(uint64(tokenId));
                }
                amount = curAmount;
            } catch {
                withdrawalRequests[vault].tokenIds.push(uint64(tokenId));
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
        uint256 length = underlyingVaults.length;
        for (uint256 i; i < length; ++i) {
            amount = IERC4626(underlyingVaults[i]).previewRedeem(amount);
        }
        return amount;
    }

    /// @dev Converts the configured base asset into current vault-asset shares with previewDeposit.
    function _convertToShare(uint256 amount, bool roundUp) internal view returns (uint256) {
        for (uint256 i = underlyingVaults.length; i > 0; --i) {
            address vault = underlyingVaults[i - 1];
            amount = roundUp ? IERC4626(vault).previewWithdraw(amount) : IERC4626(vault).previewDeposit(amount);
        }
        return amount;
    }

    /* INITIALIZATION */

    /// @dev Initializes the configured base asset and network-operator pair.
    function __initialize(address initVault, bytes memory data) internal override {
        RestakingInitParams memory params = abi.decode(data, (RestakingInitParams));

        super.__initialize(initVault, abi.encode(params.initParams));
        if (asset == params.asset) {
            revert NotRestaking();
        }
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
    }
}
