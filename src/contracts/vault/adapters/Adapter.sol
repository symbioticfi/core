// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {IRegistry} from "../../../interfaces/common/IRegistry.sol";
import {IAdapter} from "../../../interfaces/vault/IAdapter.sol";
import {IVaultV2} from "../../../interfaces/vault/IVaultV2.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {FixedPointMathLib as Math} from "@solady/src/utils/FixedPointMathLib.sol";

/// @title Adapter
/// @notice Base contract for vault adapters with shared vault validation.
abstract contract Adapter is Initializable, OwnableUpgradeable, IAdapter {
    using Math for uint256;

    /* IMMUTABLES */

    /// @notice Registry that validates whether an address is a vault.
    address public immutable VAULT_FACTORY;

    /* STATE VARIABLES */

    /// @inheritdoc IAdapter
    mapping(address collateral => uint256 limit) public globalLimit;

    /// @notice Total amount currently allocated to the adapter per collateral.
    mapping(address collateral => uint256 amount) public globalAllocated;

    /* MODIFIERS */

    modifier onlyVault(address vault) {
        _validateVault(vault);
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

    /// @notice Creates the adapter base.
    /// @param vaultFactory The vault registry address.
    constructor(address vaultFactory) {
        VAULT_FACTORY = vaultFactory;
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc IAdapter
    function allocatable(address vault) public view virtual returns (uint256) {
        address collateral = IVaultV2(vault).collateral();
        return globalLimit[collateral].saturatingSub(globalAllocated[collateral]);
    }

    /* PUBLIC FUNCTIONS (PROTOCOL) */

    /// @inheritdoc IAdapter
    function setGlobalLimit(address collateral, uint256 limit) public onlyOwner {
        globalLimit[collateral] = limit;

        emit SetGlobalLimit(collateral, limit);
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Reverts when `vault` is not a registered vault entity.
    /// @param vault The vault address to validate.
    function _validateVault(address vault) internal view {
        if (!IRegistry(VAULT_FACTORY).isEntity(vault)) {
            revert NotVault();
        }
    }

    /// @dev Increases the tracked allocated amount for a collateral.
    /// @param collateral The collateral being allocated.
    /// @param amount The amount to add.
    function _increaseGlobalAllocated(address collateral, uint256 amount) internal {
        globalAllocated[collateral] += amount;
    }

    /// @dev Decreases the tracked allocated amount for a collateral.
    /// @param collateral The collateral being deallocated.
    /// @param amount The amount to subtract.
    function _decreaseGlobalAllocated(address collateral, uint256 amount) internal {
        globalAllocated[collateral] -= amount;
    }

    /* INITIALIZATION */

    /// @notice Initializes adapter ownership.
    function initialize() public initializer {
        __Ownable_init(msg.sender);
    }
}
