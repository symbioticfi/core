// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAdapter} from "./IAdapter.sol";

uint16 constant REFERRAL_CODE = 0;

/**
 * @title IAaveV3Adapter
 * @notice Interface for the Aave V3 vault adapter.
 */
interface IAaveV3Adapter is IAdapter {
    /* ERRORS */

    /**
     * @notice Raised when the Aave pool has no reserve aToken for the vault asset.
     */
    error InvalidAToken();

    /* STRUCTS */

    /**
     * @notice Initialization parameters for the Aave V3 adapter.
     * @param converters Initial converters exempt from the prepared-request delay.
     */
    struct InitParams {
        address[] converters;
    }

    /* FUNCTIONS */

    /**
     * @notice Returns the Aave reserve aToken for a vault asset.
     * @return aToken Aave reserve aToken.
     */
    function aToken() external view returns (address);

    /**
     * @notice Returns the adapter-managed aToken amount.
     * @return totalATokens Adapter-managed aTokens.
     */
    function totalATokens() external view returns (uint256);
}
