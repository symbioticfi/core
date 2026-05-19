// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {IAdapter} from "../../interfaces/adapters/IAdapter.sol";
import {ICuratorRegistry} from "../../interfaces/adapters/ICuratorRegistry.sol";
import {IAllocationsDelegator} from "../../interfaces/delegator/IAllocationsDelegator.sol";
import {IDelegator} from "../../interfaces/delegator/IDelegator.sol";
import {IRegistry} from "../../interfaces/common/IRegistry.sol";
import {IVaultV2} from "../../interfaces/vault/IVaultV2.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Adapter
/// @notice Base contract for vault adapters with shared vault validation.
abstract contract Adapter is Initializable, OwnableUpgradeable, IAdapter {
    using Math for uint256;
    using SafeERC20 for IERC20;

    /* IMMUTABLES */

    /// @inheritdoc IAdapter
    address public immutable VAULT_FACTORY;
    /// @dev Curator registry used to authorize loss recovery.
    address internal immutable CURATOR_REGISTRY;

    /* STATE VARIABLES */

    /// @inheritdoc IAdapter
    mapping(address collateral => uint256 limit) public globalLimit;

    /// @inheritdoc IAdapter
    mapping(address collateral => uint256 amount) public globalAllocated;

    /* TRANSIENT STATE VARIABLES */

    /// @dev Marks recovery-triggered deallocations so accounting skips the normal path.
    bool internal transient _isRecover;

    /* MODIFIERS */

    modifier onlyVault(address vault) {
        _validateVault(vault);
        _;
    }

    modifier onlyCurator(address vault) {
        if (ICuratorRegistry(CURATOR_REGISTRY).getCurator(vault) != msg.sender) {
            revert NotCurator();
        }
        _;
    }

    /* MULTICALL */

    /// @inheritdoc IAdapter
    function multicall(bytes[] calldata data) public {
        for (uint256 i; i < data.length; ++i) {
            (bool success, bytes memory returnData) = address(this).delegatecall(data[i]);
            if (!success) {
                assembly ("memory-safe") {
                    revert(add(32, returnData), mload(returnData))
                }
            }
        }
    }

    /* CONSTRUCTOR */

    constructor(address vaultFactory, address curatorRegistry) {
        VAULT_FACTORY = vaultFactory;
        CURATOR_REGISTRY = curatorRegistry;
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc IAdapter
    function allocatable(address vault) public view virtual returns (uint256) {
        address collateral = IVaultV2(vault).collateral();
        return globalLimit[collateral].saturatingSub(globalAllocated[collateral]);
    }

    /// @inheritdoc IAdapter
    function totalAssets(address vault) public view virtual returns (uint256);

    /* PUBLIC FUNCTIONS (PERMISSIONLESS) */

    /// @inheritdoc IAdapter
    function skim(address vault) public onlyVault(vault) returns (uint256 amount) {
        return _skim(vault);
    }

    /* PUBLIC FUNCTIONS (CURATOR) */

    /// @inheritdoc IAdapter
    function recover(address vault, uint256 amount) public onlyVault(vault) onlyCurator(vault) {
        if (amount == 0) {
            revert ZeroAmount();
        }

        IERC20(IVaultV2(vault).collateral()).safeTransferFrom(msg.sender, address(this), amount);
        _recover(vault, amount);
        skim(vault);

        emit Recover(vault, amount);
    }

    /* PUBLIC FUNCTIONS (INTERNAL) */

    /// @inheritdoc IAdapter
    function allocate(uint256 amount) public {
        address vault = IDelegator(msg.sender).vault();
        _validateVault(vault);
        if (IVaultV2(vault).delegator() != msg.sender) {
            revert NotVault();
        }

        _allocate(vault, amount);
    }

    /// @inheritdoc IAdapter
    function deallocate(uint256 amount) public returns (uint256) {
        address vault = IDelegator(msg.sender).vault();
        _validateVault(vault);
        if (IVaultV2(vault).delegator() != msg.sender) {
            revert NotVault();
        }

        if (_isRecover) {
            address collateral = IVaultV2(vault).collateral();
            _decreaseGlobalAllocated(collateral, amount);
            if (IERC20(collateral).allowance(address(this), vault) < amount) {
                IERC20(collateral).forceApprove(vault, type(uint256).max);
            }
            return amount;
        }
        return _deallocate(vault, amount);
    }

    /* PUBLIC FUNCTIONS (PROTOCOL) */

    /// @inheritdoc IAdapter
    function setGlobalLimit(address collateral, uint256 limit) public onlyOwner {
        globalLimit[collateral] = limit;

        emit SetGlobalLimit(collateral, limit);
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Reverts when `vault` is not a registered vault entity.
    function _validateVault(address vault) internal view {
        if (!IRegistry(VAULT_FACTORY).isEntity(vault)) {
            revert NotVault();
        }
    }

    /// @dev Returns the delegator-tracked allocation for this adapter and vault.
    function _adapterAllocated(address vault) internal view returns (uint256) {
        return IAllocationsDelegator(IVaultV2(vault).delegator()).adapterAllocated(address(this));
    }

    /// @dev Increases the tracked allocated amount for a collateral.
    function _increaseGlobalAllocated(address collateral, uint256 amount) internal {
        globalAllocated[collateral] += amount;
    }

    /// @dev Decreases the tracked allocated amount for a collateral.
    function _decreaseGlobalAllocated(address collateral, uint256 amount) internal {
        globalAllocated[collateral] -= amount;
    }

    /// @dev Recovers collateral back to the vault via the delegator deallocation hook.
    function _recover(address vault, uint256 amount) internal {
        _isRecover = true;
        _deallocateAdapter(vault, amount);
        _isRecover = false;
    }

    /// @dev Deallocates this adapter through the vault's allocations delegator.
    function _deallocateAdapter(address vault, uint256 amount) internal returns (uint256) {
        return IAllocationsDelegator(IVaultV2(vault).delegator()).deallocateAdapter(address(this), amount);
    }

    /// @dev Skims excess collateral yield from the adapter for a vault.
    function _skim(address vault) internal virtual returns (uint256);

    /// @dev Allocates collateral from a vault into the adapter position.
    function _allocate(address vault, uint256 amount) internal virtual;

    /// @dev Deallocates collateral from a vault's adapter position.
    function _deallocate(address vault, uint256 amount) internal virtual returns (uint256);

    /* INITIALIZATION */

    /// @dev Initializes adapter ownership.
    function initialize() public initializer {
        __Ownable_init(msg.sender);
    }

    /* STORAGE GAP */

    /// @dev Reserved storage gap for future upgrades.
    uint256[50] internal __gap;
}
