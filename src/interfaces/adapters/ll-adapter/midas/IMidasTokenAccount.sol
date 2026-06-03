// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IMidasTokenAccount
 * @notice Interface for token-specific Midas liquidity lane accounts.
 */
interface IMidasTokenAccount {
    /* FUNCTIONS */

    /**
     * @notice Returns the maximum Midas withdrawal delay for the token.
     * @return delay The maximum withdrawal delay.
     */
    function MAX_WITHDRAWAL_DELAY() external view returns (uint48 delay);
}
