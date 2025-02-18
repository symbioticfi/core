// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IVaultTokenized is IERC20, IERC20Metadata, IERC20Errors {
    /**
     * @notice Initial parameters needed for a tokenized vault deployment.
     * @param baseParams initial parameters needed for a vault deployment (abi.encode(IVault.InitParams))
     * @param name name for the ERC20 tokenized vault
     * @param symbol symbol for the ERC20 tokenized vault
     */
    struct InitParamsTokenized {
        bytes baseParams;
        string name;
        string symbol;
    }

    /**
     * @notice Parameters needed for a tokenized vault migration.
     * @param baseParams parameters needed for a vault migration (abi.encode(IVault.MigrateParams))
     * @param name name for the ERC20 tokenized vault
     * @param symbol symbol for the ERC20 tokenized vault
     * @dev Version 1 -> version 3 vaults migration.
     */
    struct MigrateParamsTokenized {
        bytes baseParams;
        string name;
        string symbol;
    }
}
