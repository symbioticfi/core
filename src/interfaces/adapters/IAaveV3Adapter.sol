// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAdapter} from "./IAdapter.sol";

uint16 constant REFERRAL_CODE = 0;

/**
 * @title IAaveV3Adapter
 * @notice Interface for the Aave V3 vault adapter.
 */
interface IAaveV3Adapter is IAdapter {
    /* EVENTS */

    /**
     * @notice Emitted when the adapter deploys a deterministic account for a vault.
     * @param vault Vault address.
     * @param account Deterministic account address.
     */
    event DeployAccount(address indexed vault, address indexed account);

    /* FUNCTIONS */

    /**
     * @notice Returns the Aave reserve aToken for a vault collateral.
     * @param vault Vault address.
     * @return aToken Aave reserve aToken.
     */
    function aToken(address vault) external view returns (address);

    /**
     * @notice Returns the deterministic account used to hold a vault's Aave position.
     * @param vault Vault address.
     * @return account Deterministic account address.
     */
    function getAccount(address vault) external view returns (address account);
}
