// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Adapter} from "./Adapter.sol";

import {DEALLOCATE_BUFFER, IMorphoVaultV2Adapter} from "../../interfaces/adapters/IMorphoVaultV2Adapter.sol";
import {IAdapter} from "../../interfaces/adapters/IAdapter.sol";
import {IMorphoLiquidityAdapter} from "../../interfaces/adapters/morpho_vaultv2_adapter/IMorphoLiquidityAdapter.sol";
import {IMorphoVaultV2Factory} from "../../interfaces/adapters/morpho_vaultv2_adapter/IMorphoVaultV2Factory.sol";
import {IMorphoVaultV2} from "../../interfaces/adapters/morpho_vaultv2_adapter/IMorphoVaultV2.sol";
import {IRewards} from "../../interfaces/vault/IRewards.sol";
import {IVaultV2} from "../../interfaces/vault/IVaultV2.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title MorphoVaultV2Adapter
/// @notice VaultV2 adapter for Morpho ERC4626 vaults.
contract MorphoVaultV2Adapter is Initializable, Adapter, IMorphoVaultV2Adapter {
    using Math for uint256;
    using SafeERC20 for IERC20;

    /* IMMUTABLES */

    /// @dev Morpho vault factory used for curator-side vault validation.
    address internal immutable MORPHO_VAULT_FACTORY;
    /// @dev Beacon for deterministic Morpho vault accounts.
    address internal immutable BEACON;
    /// @dev Required Morpho adapter registry for configured vaults.
    address internal immutable MORPHO_ADAPTER_REGISTRY;
    /// @dev Rewards contract that receives skimmed adapter yield.
    address internal immutable REWARDS;

    /* STATE VARIABLES */

    /// @inheritdoc IMorphoVaultV2Adapter
    mapping(address vault => address morphoVault) public morphoVaults;

    /* TRANSIENT STATE VARIABLES */

    /// @dev Allows curator-driven withdrawals to bypass the normal underwater guard.
    bool internal transient _isForceDeallocate;

    /* CONSTRUCTOR */

    constructor(
        address morphoVaultFactory,
        address morphoAdapterRegistry,
        address curatorRegistry,
        address rewards,
        address vaultFactory,
        address beacon
    ) Adapter(vaultFactory, curatorRegistry) {
        MORPHO_VAULT_FACTORY = morphoVaultFactory;
        BEACON = beacon;
        MORPHO_ADAPTER_REGISTRY = morphoAdapterRegistry;
        REWARDS = rewards;
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc IAdapter
    function skimmable(address vault) public view returns (uint256) {
        return totalAssets(vault).saturatingSub(_adapterAllocated(vault));
    }

    /// @inheritdoc IAdapter
    function allocatable(address vault) public view override(Adapter, IAdapter) returns (uint256) {
        if (morphoVaults[vault] == address(0)) {
            return 0;
        }
        return super.allocatable(vault);
    }

    /// @inheritdoc IAdapter
    function deallocatable(address vault) public view returns (uint256) {
        address morphoVault = morphoVaults[vault];
        if (morphoVault == address(0)) {
            return 0;
        }
        uint256 assets = totalAssets(vault);
        uint256 allocated = _adapterAllocated(vault);
        if (!_isForceDeallocate && allocated.saturatingSub(assets) > DEALLOCATE_BUFFER) {
            return 0;
        }
        address collateral = IMorphoVaultV2(morphoVault).asset();
        address liquidityAdapter = IMorphoVaultV2(morphoVault).liquidityAdapter();
        return Math.min(
            Math.min(
                assets,
                IERC20(collateral).balanceOf(morphoVault)
                    + (liquidityAdapter == address(0) ? 0 : IMorphoLiquidityAdapter(liquidityAdapter).realAssets())
            ),
            allocated
        );
    }

    /// @inheritdoc IMorphoVaultV2Adapter
    function getAccount(address vault) public view returns (address account) {
        return Create2.computeAddress(_accountSalt(vault), _accountProxyInitCodeHash(), address(this));
    }

    /// @inheritdoc IAdapter
    function totalAssets(address vault) public view override(Adapter, IAdapter) returns (uint256) {
        address morphoVault = morphoVaults[vault];
        if (morphoVault == address(0)) {
            return 0;
        }
        return IMorphoVaultV2(morphoVault).previewRedeem(IMorphoVaultV2(morphoVault).balanceOf(getAccount(vault)));
    }

    /* PUBLIC FUNCTIONS (CURATOR) */

    /// @inheritdoc IMorphoVaultV2Adapter
    function forceDeallocate(address vault, uint256 amount)
        public
        onlyVault(vault)
        onlyCurator(vault)
        returns (uint256 deallocated)
    {
        if (amount == 0) {
            revert InsufficientAmount();
        }

        _isForceDeallocate = true;
        deallocated = _deallocateAdapter(vault, amount);
        _isForceDeallocate = false;

        emit ForceDeallocate(vault, amount, deallocated);
    }

    /// @inheritdoc IMorphoVaultV2Adapter
    function setMorphoVault(address vault, address newMorphoVault) public onlyVault(vault) onlyCurator(vault) {
        if (
            newMorphoVault != address(0)
                && (!IMorphoVaultV2Factory(MORPHO_VAULT_FACTORY).isVaultV2(newMorphoVault)
                    || IMorphoVaultV2(newMorphoVault).adapterRegistry() != MORPHO_ADAPTER_REGISTRY
                    || !IMorphoVaultV2(newMorphoVault).abdicated(IMorphoVaultV2.setAdapterRegistry.selector)
                    || IMorphoVaultV2(newMorphoVault).asset() != IVaultV2(vault).collateral())
        ) {
            revert InvalidMorphoVault();
        }
        address curMorphoVault = morphoVaults[vault];
        if (curMorphoVault != address(0) && totalAssets(vault) > 0) {
            revert ActivePosition();
        }
        morphoVaults[vault] = newMorphoVault;

        emit SetMorphoVault(vault, newMorphoVault);
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Withdraws excess Morpho yield back to the adapter and forwards it to rewards.
    function _skim(address vault) internal override returns (uint256 amount) {
        amount = skimmable(vault);
        if (amount == 0) {
            return 0;
        }
        address morphoVault = morphoVaults[vault];
        try MorphoVaultV2Account(_deployAccount(vault)).withdraw(morphoVault, amount) {}
        catch {
            return 0;
        }
        address collateral = IMorphoVaultV2(morphoVault).asset();
        if (IERC20(collateral).allowance(address(this), REWARDS) < amount) {
            IERC20(collateral).forceApprove(REWARDS, type(uint256).max);
        }
        IRewards(REWARDS).distributeDonationRewards(vault, amount);
    }

    /// @dev Deposits collateral from the calling vault into the configured Morpho vault.
    function _allocate(address vault, uint256 amount) internal override {
        _skim(vault);
        if (skimmable(vault) > 0) {
            revert SkimFailed();
        }

        if (amount == 0) {
            return;
        }

        address morphoVault = morphoVaults[vault];
        address collateral = IMorphoVaultV2(morphoVault).asset();
        _increaseGlobalAllocated(collateral, amount);

        if (IERC20(collateral).allowance(address(this), morphoVault) < amount) {
            IERC20(collateral).forceApprove(morphoVault, type(uint256).max);
        }
        try this.deposit(morphoVault, amount, getAccount(vault)) {
            return;
        } catch {}

        _recover(vault, amount);
    }

    /// @dev Uses an external self-call so zero-share deposits revert and roll back the Morpho transfer.
    function deposit(address morphoVault, uint256 amount, address onBehalfOf) external {
        if (address(this) != msg.sender) {
            revert NotSelf();
        }
        if (IMorphoVaultV2(morphoVault).deposit(amount, onBehalfOf) == 0) {
            revert InsufficientAmount();
        }
    }

    /// @dev Withdraws collateral for the calling vault from the configured Morpho vault.
    function _deallocate(address vault, uint256 amount) internal override returns (uint256) {
        _skim(vault);

        if (amount == 0) {
            return 0;
        }

        amount = Math.min(deallocatable(vault), amount);
        if (amount == 0) {
            return 0;
        }

        address morphoVault = morphoVaults[vault];
        address collateral = IMorphoVaultV2(morphoVault).asset();
        try MorphoVaultV2Account(_deployAccount(vault)).withdraw(morphoVault, amount) {
            _decreaseGlobalAllocated(collateral, amount);
            if (IERC20(collateral).allowance(address(this), vault) < amount) {
                IERC20(collateral).forceApprove(vault, type(uint256).max);
            }
        } catch {
            amount = 0;
        }

        return amount;
    }

    /// @dev Deploys the deterministic Morpho holding account for a vault on first use.
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

contract MorphoVaultV2Account {
    error NotAdapter();

    /// @dev Adapter authorized to operate the account.
    address internal immutable ADAPTER;

    constructor(address adapter) {
        ADAPTER = adapter;
    }

    modifier onlyAdapter() {
        if (ADAPTER != msg.sender) {
            revert NotAdapter();
        }
        _;
    }

    function withdraw(address morphoVault, uint256 assets) external onlyAdapter {
        IMorphoVaultV2(morphoVault).withdraw(assets, ADAPTER, address(this));
    }
}
