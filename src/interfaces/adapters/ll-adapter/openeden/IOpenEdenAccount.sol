// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ICooldownAccount} from "../ICooldownAccount.sol";

/// @dev Maximum final redeem queue length inspected for locked redemption values.
uint256 constant MAX_REDEEM_QUEUE_LENGTH = 30;

/**
 * @title IOpenEdenAccount
 * @notice Interface for OpenEden liquidity lane accounts.
 */
interface IOpenEdenAccount is ICooldownAccount {
    /* ERRORS */

    /**
     * @notice Raised when the OpenEden redeem asset is not the vault asset.
     */
    error InvalidAsset();

    /* FUNCTIONS */

    /**
     * @notice Returns the HYBONDExpress contract.
     * @return express The HYBONDExpress address.
     */
    function EXPRESS() external view returns (address express);
}
