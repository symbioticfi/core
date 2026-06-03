// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAccount} from "../IAccount.sol";

/**
 * @title IHumaAccount
 * @notice Interface for Huma liquidity lane accounts.
 */
interface IHumaAccount is IAccount {
    /* FUNCTIONS */

    /**
     * @notice Returns the Huma tranche vault used for redemption requests.
     * @return vault The redemption vault address.
     */
    function REDEMPTION_VAULT() external view returns (address vault);

    /**
     * @notice Returns requested value no longer held as tranche tokens.
     * @return assets The pending vault-asset value.
     */
    function pendingAssets() external view returns (uint256 assets);
}
