// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {IAdapter} from "../../../interfaces/vault/IAdapter.sol";
import {ICuratorRegistry} from "../../../interfaces/vault/adapters/ICuratorRegistry.sol";
import {IRegistry} from "../../../interfaces/common/IRegistry.sol";
import {IVaultV2} from "../../../interfaces/vault/IVaultV2.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {FixedPointMathLib as Math} from "@solady/src/utils/FixedPointMathLib.sol";
import {SafeTransferLib as SafeERC20} from "@solady/src/utils/SafeTransferLib.sol";

/// @title Adapter
/// @notice Base contract for vault adapters with shared vault validation.
abstract contract Adapter is Initializable, OwnableUpgradeable, IAdapter {
    using Math for uint256;
    using SafeERC20 for address;

    /* IMMUTABLES */

    /// @notice Registry that validates whether an address is a vault.
    address public immutable VAULT_FACTORY;
    /// @dev Curator registry used to authorize loss recovery.
    address internal immutable CURATOR_REGISTRY;

    /* STATE VARIABLES */

    /// @inheritdoc IAdapter
    mapping(address collateral => uint256 limit) public globalLimit;

    /// @notice Total amount currently allocated to the adapter per collateral.
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

    /* PUBLIC FUNCTIONS (PERMISSIONLESS) */

    /// @inheritdoc IAdapter
    function skim(address vault) public onlyVault(vault) returns (uint256 amount) {
        return _skim(vault);
    }

    /// @inheritdoc IAdapter
    function recover(address vault, uint256 amount) public onlyVault(vault) {
        if (amount == 0) {
            revert ZeroAmount();
        }

        IVaultV2(vault).collateral().safeTransferFrom(msg.sender, address(this), amount);
        _recover(vault, amount);
        skim(vault);

        emit Recover(vault, amount);
    }

    /* PUBLIC FUNCTIONS (INTERNAL) */

    /// @inheritdoc IAdapter
    function allocate(uint256 amount) public onlyVault(msg.sender) {
        _allocate(amount);
    }

    /// @inheritdoc IAdapter
    function deallocate(uint256 amount) public onlyVault(msg.sender) returns (uint256) {
        if (_isRecover) {
            address collateral = IVaultV2(msg.sender).collateral();
            _decreaseGlobalAllocated(collateral, amount);
            if (IERC20(collateral).allowance(address(this), msg.sender) < amount) {
                collateral.safeApproveWithRetry(msg.sender, type(uint256).max);
            }
            return amount;
        }
        return _deallocate(amount);
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

    /// @dev Increases the tracked allocated amount for a collateral.
    function _increaseGlobalAllocated(address collateral, uint256 amount) internal {
        globalAllocated[collateral] += amount;
    }

    /// @dev Decreases the tracked allocated amount for a collateral.
    function _decreaseGlobalAllocated(address collateral, uint256 amount) internal {
        globalAllocated[collateral] -= amount;
    }

    /// @dev Recovers collateral back to the adapter via the vault deallocation hook.
    function _recover(address vault, uint256 amount) internal {
        _isRecover = true;
        IVaultV2(vault).deallocateAdapter(address(this), amount);
        _isRecover = false;
    }

    /// @dev Skims excess collateral yield from the adapter for a vault.
    function _skim(address vault) internal virtual returns (uint256);

    /// @dev Allocates collateral from the calling vault into the adapter position.
    function _allocate(uint256 amount) internal virtual;

    /// @dev Deallocates collateral from the calling vault's adapter position.
    function _deallocate(uint256 amount) internal virtual returns (uint256);

    /* INITIALIZATION */

    /// @notice Initializes adapter ownership.
    function initialize() public initializer {
        __Ownable_init(msg.sender);
    }

    /* STORAGE GAP */

    /// @dev Reserved storage gap for future upgrades.
    uint256[50] internal __gap;
}
