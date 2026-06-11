// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ICooldownAccount} from "../ICooldownAccount.sol";

/**
 * @title IFigureAccount
 * @notice Interface for Figure/Hastra liquidity lane accounts.
 */
interface IFigureAccount is ICooldownAccount {
    /* FUNCTIONS */

    /**
     * @notice Returns pending wYLDS redemption request value in vault assets.
     * @return assets The pending vault-asset value.
     */
    function pendingAssets() external view returns (uint256 assets);
}
