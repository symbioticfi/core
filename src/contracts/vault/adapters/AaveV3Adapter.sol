// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Adapter} from "./Adapter.sol";

import {ERC4626Math} from "../../libraries/ERC4626Math.sol";

import {IAdapter} from "../../../interfaces/vault/IAdapter.sol";
import {IVaultV2} from "../../../interfaces/vault/IVaultV2.sol";
import {IAaveV3Adapter, REFERRAL_CODE} from "../../../interfaces/vault/adapters/aave_v3_adapter/IAaveV3Adapter.sol";
import {IAaveV3Pool} from "../../../interfaces/vault/adapters/aave_v3_adapter/IAaveV3AdapterDependencies.sol";
import {IRewards} from "../../../interfaces/vault/IRewards.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {FixedPointMathLib as Math} from "@solady/src/utils/FixedPointMathLib.sol";
import {SafeTransferLib as SafeERC20} from "@solady/src/utils/SafeTransferLib.sol";

/// @title AaveV3Adapter
/// @notice VaultV2 adapter for Aave V3 supply positions.
contract AaveV3Adapter is Initializable, Adapter, IAaveV3Adapter {
    using Math for uint256;
    using SafeERC20 for address;

    /* IMMUTABLES */

    /// @inheritdoc IAaveV3Adapter
    address public immutable AAVE_POOL;
    /// @notice Rewards contract that receives donated adapter yield.
    address internal immutable REWARDS;

    /* STATE VARIABLES */

    /// @inheritdoc IAaveV3Adapter
    mapping(address collateral => uint256 shares) public totalCollateralShares;
    /// @inheritdoc IAaveV3Adapter
    mapping(address collateral => mapping(address vault => uint256 shares)) public vaultShares;

    /* CONSTRUCTOR */

    /// @notice Creates the Aave adapter.
    /// @param aavePool The single Aave V3 pool used by the adapter.
    /// @param rewards The rewards contract that receives skimmed yield.
    /// @param vaultFactory The vault registry address.
    constructor(address aavePool, address rewards, address vaultFactory) Adapter(vaultFactory) {
        AAVE_POOL = aavePool;
        REWARDS = rewards;
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc IAaveV3Adapter
    function aToken(address vault) public view returns (address) {
        return IAaveV3Pool(AAVE_POOL).getReserveData(IVaultV2(vault).collateral()).aTokenAddress;
    }

    /// @inheritdoc IAdapter
    function skimmable(address vault) public view returns (uint256) {
        return _getVaultAssets(vault).saturatingSub(IVaultV2(vault).adapterAllocated(address(this)));
    }

    /// @inheritdoc IAdapter
    function allocatable(address vault) public view returns (uint256) {
        if (aToken(vault) == address(0)) {
            return 0;
        }
        return type(uint256).max;
    }

    /// @inheritdoc IAdapter
    function deallocatable(address vault) public view returns (uint256) {
        address collateral = IVaultV2(vault).collateral();
        address curAToken = aToken(vault);
        if (curAToken == address(0)) {
            return 0;
        }

        return Math.min(
            IERC20(collateral).balanceOf(address(this))
                + Math.min(_getVaultAssets(vault), IERC20(collateral).balanceOf(curAToken)),
            IVaultV2(vault).adapterAllocated(address(this))
        );
    }

    /* PUBLIC FUNCTIONS (PERMISSIONLESS) */

    /// @inheritdoc IAdapter
    function skim(address vault) public onlyVault(vault) returns (uint256 amount) {
        amount = skimmable(vault);
        if (amount > 0) {
            address collateral = IVaultV2(vault).collateral();
            uint256 burnedShares =
                ERC4626Math.previewWithdraw(amount, totalCollateralShares[collateral], _getAdapterAssets(vault));
            try IAaveV3Pool(AAVE_POOL).withdraw(collateral, amount, address(this)) returns (uint256) {
                vaultShares[collateral][vault] -= burnedShares;
                totalCollateralShares[collateral] -= burnedShares;
            } catch {
                return 0;
            }

            if (IERC20(collateral).allowance(address(this), REWARDS) < amount) {
                collateral.safeApproveWithRetry(REWARDS, type(uint256).max);
            }
            IRewards(REWARDS).distributeDonationRewards(vault, amount);
        }
    }

    /* PUBLIC FUNCTIONS (INTERNAL) */

    /// @inheritdoc IAdapter
    function allocate(uint256 amount) public onlyVault(msg.sender) {
        skim(msg.sender);

        address collateral = IVaultV2(msg.sender).collateral();
        if (aToken(msg.sender) == address(0) || amount == 0) {
            return;
        }

        if (IERC20(collateral).allowance(address(this), AAVE_POOL) < amount) {
            collateral.safeApproveWithRetry(AAVE_POOL, type(uint256).max);
        }

        uint256 mintedShares =
            ERC4626Math.previewDeposit(amount, totalCollateralShares[collateral], _getAdapterAssets(msg.sender));
        try IAaveV3Pool(AAVE_POOL).supply(collateral, amount, address(this), REFERRAL_CODE) {
            vaultShares[collateral][msg.sender] += mintedShares;
            totalCollateralShares[collateral] += mintedShares;
        } catch {
            IVaultV2(msg.sender).deallocateAdapter(address(this), amount);
        }
    }

    /// @inheritdoc IAdapter
    function deallocate(uint256 amount) public onlyVault(msg.sender) returns (uint256 deallocated) {
        skim(msg.sender);

        address collateral = IVaultV2(msg.sender).collateral();
        if (aToken(msg.sender) == address(0) || amount == 0) {
            return 0;
        }

        deallocated = Math.min(deallocatable(msg.sender), amount);
        if (deallocated > 0) {
            uint256 curBalance = IERC20(collateral).balanceOf(address(this));
            uint256 amountToWithdraw = deallocated.saturatingSub(curBalance);
            if (amountToWithdraw > 0) {
                uint256 burnedShares = ERC4626Math.previewWithdraw(
                    amountToWithdraw, totalCollateralShares[collateral], _getAdapterAssets(msg.sender)
                );
                try IAaveV3Pool(AAVE_POOL).withdraw(collateral, amountToWithdraw, address(this)) returns (uint256) {
                    vaultShares[collateral][msg.sender] -= burnedShares;
                    totalCollateralShares[collateral] -= burnedShares;
                } catch {
                    deallocated = curBalance;
                }
            }

            if (IERC20(collateral).allowance(address(this), msg.sender) < deallocated) {
                collateral.safeApproveWithRetry(msg.sender, type(uint256).max);
            }
        }
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Returns the adapter's total aToken-backed assets for the vault collateral.
    /// @param vault The vault whose collateral reserve is queried.
    /// @return assets The adapter asset balance represented in collateral units.
    function _getAdapterAssets(address vault) internal view returns (uint256) {
        address curAToken = aToken(vault);
        if (curAToken == address(0)) {
            return 0;
        }
        return IERC20(curAToken).balanceOf(address(this));
    }

    /// @dev Returns the vault's pro-rata claim on the adapter's Aave position.
    /// @param vault The vault whose share is queried.
    /// @return assets The vault asset balance represented in collateral units.
    function _getVaultAssets(address vault) internal view returns (uint256) {
        address collateral = IVaultV2(vault).collateral();
        if (aToken(vault) == address(0)) {
            return 0;
        }

        return ERC4626Math.previewRedeem(
            vaultShares[collateral][vault], _getAdapterAssets(vault), totalCollateralShares[collateral]
        );
    }

    /* INITIALIZATION */

    /// @inheritdoc IAaveV3Adapter
    function initialize() public initializer {}
}
