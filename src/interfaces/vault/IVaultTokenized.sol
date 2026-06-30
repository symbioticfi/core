// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IVault} from "./IVault.sol";

uint64 constant VAULT_TOKENIZED_VERSION = 2;

/**
 * @title IVaultTokenized
 * @notice Interface for the VaultTokenized contract.
 */
interface IVaultTokenized is IVault {
    /**
     * @notice Initial parameters needed for a tokenized vault deployment.
     * @param baseParams Initial parameters needed for a vault deployment (InitParams).
     * @param name Name for the ERC20 tokenized vault.
     * @param symbol Symbol for the ERC20 tokenized vault.
     */
    struct InitParamsTokenized {
        InitParams baseParams;
        string name;
        string symbol;
    }
}
