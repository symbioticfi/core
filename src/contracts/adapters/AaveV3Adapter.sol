// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Adapter} from "./Adapter.sol";

import {IAaveV3Adapter, REFERRAL_CODE} from "../../interfaces/adapters/IAaveV3Adapter.sol";
import {IAaveV3Pool} from "../../interfaces/adapters/aave_v3_adapter/IAaveV3AdapterDependencies.sol";
import {IAdapter} from "../../interfaces/adapters/IAdapter.sol";
import {IRewards} from "../../interfaces/vault/IRewards.sol";
import {IVaultV2} from "../../interfaces/vault/IVaultV2.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title AaveV3Adapter
/// @notice VaultV2 adapter for Aave V3 supply positions.
contract AaveV3Adapter is Initializable, Adapter, IAaveV3Adapter {
    using Math for uint256;
    using SafeERC20 for IERC20;

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
        return totalAssets(vault).saturatingSub(_adapterAllocated(vault));
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
                totalAssets(vault), IAaveV3Pool(AAVE_POOL).getVirtualUnderlyingBalance(IVaultV2(vault).collateral())
            ),
            _adapterAllocated(vault)
        );
    }

    /// @inheritdoc IAaveV3Adapter
    function getAccount(address vault) public view returns (address account) {
        return Create2.computeAddress(_accountSalt(vault), _accountProxyInitCodeHash(), address(this));
    }

    /// @inheritdoc IAdapter
    function totalAssets(address vault) public view override(Adapter, IAdapter) returns (uint256) {
        if (aToken(vault) == address(0)) {
            return 0;
        }
        return IERC20(aToken(vault)).balanceOf(getAccount(vault));
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
            IERC20(collateral).forceApprove(REWARDS, type(uint256).max);
        }
        IRewards(REWARDS).distributeDonationRewards(vault, amount);
    }

    /// @dev Supplies collateral from the calling vault into Aave.
    function _allocate(address vault, uint256 amount) internal override {
        _skim(vault);
        if (skimmable(vault) > 0) {
            revert SkimFailed();
        }

        if (amount == 0) {
            return;
        }

        address collateral = IVaultV2(vault).collateral();
        _increaseGlobalAllocated(collateral, amount);

        if (IERC20(collateral).allowance(address(this), AAVE_POOL) < amount) {
            IERC20(collateral).forceApprove(AAVE_POOL, type(uint256).max);
        }
        try IAaveV3Pool(AAVE_POOL).supply(collateral, amount, getAccount(vault), REFERRAL_CODE) {
            return;
        } catch {}

        _recover(vault, amount);
    }

    /// @dev Withdraws collateral for the calling vault from Aave when liquidity is available.
    function _deallocate(address vault, uint256 amount) internal override returns (uint256) {
        _skim(vault);

        if (amount == 0) {
            return 0;
        }

        amount = Math.min(deallocatable(vault), amount);
        if (amount == 0) {
            return 0;
        }

        address collateral = IVaultV2(vault).collateral();
        try AaveV3Account(_deployAccount(vault)).withdraw(collateral, amount) {
            _decreaseGlobalAllocated(collateral, amount);
            if (IERC20(collateral).allowance(address(this), vault) < amount) {
                IERC20(collateral).forceApprove(vault, type(uint256).max);
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
        account = address(new BeaconProxy{salt: _accountSalt(vault)}(BEACON, ""));

        emit DeployAccount(vault, account);
    }

    /// @dev Computes the OZ BeaconProxy creation-code hash for this adapter's beacon.
    function _accountProxyInitCodeHash() internal view returns (bytes32) {
        return keccak256(abi.encodePacked(type(BeaconProxy).creationCode, abi.encode(BEACON, "")));
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
