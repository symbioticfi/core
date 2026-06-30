// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ICooldownAccount} from "../ICooldownAccount.sol";

/**
 * @title INoonAccount
 * @notice Interface for Noon liquidity lane accounts.
 */
interface INoonAccount is ICooldownAccount {
    /* ERRORS */

    /**
     * @notice Raised when the Noon withdrawal asset is not the vault asset.
     */
    error InvalidAsset();

    /* FUNCTIONS */

    /**
     * @notice Returns the Noon withdrawal handler.
     * @return withdrawalHandler The withdrawal handler address.
     */
    function WITHDRAWAL_HANDLER() external view returns (address withdrawalHandler);

    /**
     * @notice Returns a Noon withdrawal request id by index.
     * @param index The request index.
     * @return requestId The withdrawal request id.
     */
    function requestIds(uint256 index) external view returns (uint256 requestId);
}
