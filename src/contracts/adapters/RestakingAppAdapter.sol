// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {AppAdapter} from "./AppAdapter.sol";

import {Subnetwork} from "../libraries/Subnetwork.sol";

import {IAppAdapter} from "../../interfaces/adapters/IAppAdapter.sol";
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
    address[] public vaults;

    struct WithdrawalRequests {
        uint256 firstUnclaimed;
        uint16[] tokenIds;
    }

    mapping(address vault => WithdrawalRequests) public withdrawalRequests;

    /* CONSTRUCTOR */

    constructor(address vaultFactory, address adapterFactory, address curatorRegistry, address networkMiddlewareService)
        AppAdapter(vaultFactory, adapterFactory, curatorRegistry, networkMiddlewareService)
    {}

    /* VIEW FUNCTIONS */

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
        for (uint256 i = vaults.length; i > 0; --i) {
            if (IERC20(token).allowance(address(this), vaults[i - 1]) < amount) {
                IERC20(token).forceApprove(vaults[i - 1], type(uint256).max);
            }
            amount = IERC4626(vaults[i - 1]).deposit(amount, address(this));
            token = vaults[i - 1];
        }
    }

    /// @inheritdoc IRestakingAppAdapter
    function syncSlash() public {
        for (uint256 i; i < vaults.length; ++i) {
            WithdrawalRequests storage requests = withdrawalRequests[vaults[i]];
            IWithdrawalQueue withdrawalQueue = IWithdrawalQueue(IVaultV2(vaults[i]).withdrawalQueue());
            for (; requests.firstUnclaimed < requests.tokenIds.length; ++requests.firstUnclaimed) {
                uint256 tokenId = requests.tokenIds[requests.firstUnclaimed];
                (uint256 amount,) = withdrawalQueue.claim(tokenId);
                if (amount > 0) {
                    _sendToBurner(i + 1, amount);
                }
                if (!withdrawalQueue.isClaimed(tokenId)) {
                    break;
                }
            }
        }
    }

    /* INTERNAL FUNCTIONS */

    /// @inheritdoc AppAdapter
    function _sendToBurner(uint256 amount) internal override {
        _sendToBurner(0, amount);
    }

    function _sendToBurner(uint256 index, uint256 amount) internal {
        for (uint256 i = index; i < vaults.length; ++i) {
            address withdrawalQueue = IVaultV2(vaults[i]).withdrawalQueue();
            if (IERC20(vaults[i]).allowance(address(this), withdrawalQueue) < amount) {
                IERC20(vaults[i]).forceApprove(withdrawalQueue, type(uint256).max);
            }
            uint256 tokenId = IWithdrawalQueue(withdrawalQueue).requestRedeem(amount, address(this));
            try IWithdrawalQueue(withdrawalQueue).claim(tokenId) returns (uint256 curAmount, uint256 shares) {
                if (shares < amount) {
                    withdrawalRequests[vaults[i]].tokenIds.push(uint16(tokenId));
                }
                amount = curAmount;
            } catch {
                withdrawalRequests[vaults[i]].tokenIds.push(uint16(tokenId));
                return;
            }
        }
        super._sendToBurner(amount);
    }

    /// @dev Initializes the configured base asset and network-operator pair.
    function __initialize(address initVault, bytes memory data) internal override {
        RestakingInitParams memory params = abi.decode(data, (RestakingInitParams));

        super.__initialize(initVault, abi.encode(params.initParams));

        asset = params.asset;
        vaults.push(vault);
        address curAsset = IERC4626(vault).asset();
        for (uint256 depth; curAsset != params.asset && depth < MAX_DEPTH; ++depth) {
            if (!IRegistry(VAULT_FACTORY).isEntity(curAsset)) {
                revert InvalidBaseAsset();
            }
            vaults.push(curAsset);
            curAsset = IERC4626(curAsset).asset();
        }
        if (curAsset != params.asset) {
            revert InvalidAsset();
        }
    }

    /// @dev Converts current vault-asset shares into the configured base asset with previewRedeem.
    function _convertToAsset(uint256 amount) internal view returns (uint256) {
        for (uint256 i; i < vaults.length; ++i) {
            amount = IERC4626(vaults[i]).previewRedeem(amount);
        }
        return amount;
    }
}
