// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Adapter} from "./Adapter.sol";

import {IAaveV3Adapter, REFERRAL_CODE} from "../../../interfaces/vault/adapters/IAaveV3Adapter.sol";
import {IAaveV3Pool} from "../../../interfaces/vault/adapters/aave_v3_adapter/IAaveV3AdapterDependencies.sol";
import {IAdapter} from "../../../interfaces/vault/adapters/IAdapter.sol";
import {IRewards} from "../../../interfaces/vault/IRewards.sol";
import {IVaultV2} from "../../../interfaces/vault/IVaultV2.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {FixedPointMathLib as Math} from "@solady/src/utils/FixedPointMathLib.sol";
import {LibClone as Clones} from "@solady/src/utils/LibClone.sol";
import {SafeTransferLib as SafeERC20} from "@solady/src/utils/SafeTransferLib.sol";

/// @title AaveV3Adapter
/// @notice VaultV2 adapter for Aave V3 supply positions.
contract AaveV3Adapter is Initializable, Adapter, IAaveV3Adapter {
    using Math for uint256;
    using Clones for address;
    using SafeERC20 for address;

    /* IMMUTABLES */

    /// @dev Core Aave V3 pool.
    address internal immutable AAVE_POOL;
    /// @dev Beacon for deterministic Aave vault accounts.
    address internal immutable BEACON;
    /// @dev Rewards contract that redistributes adapter yield to the vault.
    address internal immutable REWARDS;

    /* CONSTRUCTOR */

    constructor(address aavePool, address curatorRegistry, address rewards, address vaultFactory, address beacon)
        Adapter(vaultFactory, curatorRegistry)
    {
        AAVE_POOL = aavePool;
        BEACON = beacon;
        REWARDS = rewards;
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc IAaveV3Adapter
    function aToken(address vault) public view returns (address) {
        return IAaveV3Pool(AAVE_POOL).getReserveAToken(IVaultV2(vault).collateral());
    }

    /// @inheritdoc IAdapter
    function skimmable(address vault) public view returns (uint256) {
        return getAssets(vault).saturatingSub(IVaultV2(vault).adapterAllocated(address(this)));
    }

    /// @inheritdoc IAdapter
    function allocatable(address vault) public view override(Adapter, IAdapter) returns (uint256) {
        if (aToken(vault) == address(0)) {
            return 0;
        }
        return super.allocatable(vault);
    }

    /// @inheritdoc IAdapter
    function deallocatable(address vault) public view returns (uint256) {
        if (aToken(vault) == address(0)) {
            return 0;
        }
        return Math.min(
            Math.min(
                getAssets(vault), IAaveV3Pool(AAVE_POOL).getVirtualUnderlyingBalance(IVaultV2(vault).collateral())
            ),
            IVaultV2(vault).adapterAllocated(address(this))
        );
    }

    /// @inheritdoc IAaveV3Adapter
    function getAccount(address vault) public view returns (address account) {
        return BEACON.predictDeterministicAddressERC1967IBeaconProxy(_accountSalt(vault), address(this));
    }

    /// @inheritdoc IAaveV3Adapter
    function getAssets(address vault) public view returns (uint256) {
        if (aToken(vault) == address(0)) {
            return 0;
        }
        return aToken(vault).balanceOf(getAccount(vault));
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Withdraws excess Aave yield back to the adapter and forwards it to rewards.
    function _skim(address vault) internal override returns (uint256 amount) {
        amount = skimmable(vault);
        if (amount == 0) {
            return 0;
        }
        address collateral = IVaultV2(vault).collateral();
        try AaveV3Account(_deployAccount(vault)).withdraw(collateral, amount) {}
        catch {
            return 0;
        }

        if (IERC20(collateral).allowance(address(this), REWARDS) < amount) {
            collateral.safeApproveWithRetry(REWARDS, type(uint256).max);
        }
        IRewards(REWARDS).distributeDonationRewards(vault, amount);
    }

    /// @dev Supplies collateral from the calling vault into Aave.
    function _allocate(uint256 amount) internal override {
        _skim(msg.sender);
        if (skimmable(msg.sender) > 0) {
            revert SkimFailed();
        }

        if (amount == 0) {
            return;
        }

        address collateral = IVaultV2(msg.sender).collateral();
        _increaseGlobalAllocated(collateral, amount);

        if (IERC20(collateral).allowance(address(this), AAVE_POOL) < amount) {
            collateral.safeApproveWithRetry(AAVE_POOL, type(uint256).max);
        }
        try IAaveV3Pool(AAVE_POOL).supply(collateral, amount, getAccount(msg.sender), REFERRAL_CODE) {
            return;
        } catch {}

        _recover(msg.sender, amount);
    }

    /// @dev Withdraws collateral for the calling vault from Aave when liquidity is available.
    function _deallocate(uint256 amount) internal override returns (uint256) {
        _skim(msg.sender);

        if (amount == 0) {
            return 0;
        }

        amount = Math.min(deallocatable(msg.sender), amount);
        if (amount == 0) {
            return 0;
        }

        address collateral = IVaultV2(msg.sender).collateral();
        try AaveV3Account(_deployAccount(msg.sender)).withdraw(collateral, amount) {
            _decreaseGlobalAllocated(collateral, amount);
            if (IERC20(collateral).allowance(address(this), msg.sender) < amount) {
                collateral.safeApproveWithRetry(msg.sender, type(uint256).max);
            }
        } catch {
            amount = 0;
        }

        return amount;
    }

    /// @dev Deploys the deterministic Aave holding account for a vault on first use.
    function _deployAccount(address vault) internal returns (address account) {
        account = getAccount(vault);
        if (account.code.length > 0) {
            return account;
        }
        account = BEACON.deployDeterministicERC1967IBeaconProxy(_accountSalt(vault));

        emit DeployAccount(vault, account);
    }

    /// @dev Derives the deterministic clone salt for a vault account.
    function _accountSalt(address vault) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(vault)));
    }
}

contract AaveV3Account {
    error NotAdapter();

    /// @dev Aave V3 pool used for withdrawals.
    address internal immutable AAVE_POOL;
    /// @dev Adapter authorized to operate the account.
    address internal immutable ADAPTER;

    constructor(address aavePool, address adapter) {
        AAVE_POOL = aavePool;
        ADAPTER = adapter;
    }

    modifier onlyAdapter() {
        if (ADAPTER != msg.sender) {
            revert NotAdapter();
        }
        _;
    }

    function withdraw(address asset, uint256 amount) external onlyAdapter {
        IAaveV3Pool(AAVE_POOL).withdraw(asset, amount, ADAPTER);
    }
}
