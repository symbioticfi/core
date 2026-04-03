// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {IRegistry} from "../../../interfaces/common/IRegistry.sol";
import {IAdapter} from "../../../interfaces/vault/IAdapter.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title Adapter
/// @notice Base contract for vault adapters with shared vault validation.
abstract contract Adapter is Initializable, OwnableUpgradeable, IAdapter {
    /* IMMUTABLES */

    /// @notice Registry that validates whether an address is a vault.
    address public immutable VAULT_FACTORY;

    /* MODIFIERS */

    modifier onlyVault(address vault) {
        _validateVault(vault);
        _;
    }

    /* MULTICALL */

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

    /* INTERNAL FUNCTIONS */

    /// @dev Reverts when `vault` is not a registered vault entity.
    /// @param vault The vault address to validate.
    function _validateVault(address vault) internal view {
        if (!IRegistry(VAULT_FACTORY).isEntity(vault)) {
            revert NotVault();
        }
    }
}
