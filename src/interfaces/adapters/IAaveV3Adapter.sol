// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAdapter} from "./IAdapter.sol";

uint16 constant REFERRAL_CODE = 0;

/**
 * @title IAaveV3Adapter
 * @notice Interface for the Aave V3 vault adapter.
 */
interface IAaveV3Adapter is IAdapter {
    /* FUNCTIONS */

    /**
     * @notice Returns the Aave reserve aToken for a vault collateral.
     * @return aToken Aave reserve aToken.
     */
    function aToken() external view returns (address);
}
