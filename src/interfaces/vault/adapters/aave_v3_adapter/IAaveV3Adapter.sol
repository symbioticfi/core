// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAdapter} from "../../IAdapter.sol";

uint16 constant REFERRAL_CODE = 0;

/**
 * @title IAaveV3Adapter
 * @notice Interface for the Aave V3 vault adapter.
 */
interface IAaveV3Adapter is IAdapter {
    /* FUNCTIONS */

    /**
     * @notice Returns the Aave reserve aToken for a vault collateral.
     * @param vault Vault address.
     * @return aToken Aave reserve aToken.
     */
    function aToken(address vault) external view returns (address);

    /**
     * @notice Returns the total adapter share supply tracked for a collateral token.
     * @param collateral Vault collateral token.
     * @return Total tracked shares.
     */
    function totalCollateralShares(address collateral) external view returns (uint256);

    /**
     * @notice Returns the tracked shares of a vault for a collateral token.
     * @param collateral Vault collateral token.
     * @param vault Vault address.
     * @return Tracked vault shares.
     */
    function vaultShares(address collateral, address vault) external view returns (uint256);
}
