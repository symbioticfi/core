// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IAcredAccount
 * @notice Interface for ACRED liquidity lane accounts.
 */
interface IAcredAccount {
    /* FUNCTIONS */

    /**
     * @notice Returns the wallet receiving ACRED redemption transfers.
     * @return wallet The redemption wallet address.
     */
    function REDEMPTION_WALLET() external view returns (address wallet);

    /**
     * @notice Returns ACRED redemption configuration point 0.
     * @return point The configuration point.
     */
    function POINT_0() external view returns (uint48 point);

    /**
     * @notice Returns ACRED redemption configuration point 1.
     * @return point The configuration point.
     */
    function POINT_1() external view returns (uint48 point);

    /**
     * @notice Returns ACRED redemption configuration point 2.
     * @return point The configuration point.
     */
    function POINT_2() external view returns (uint48 point);

    /**
     * @notice Returns ACRED redemption configuration point 3.
     * @return point The configuration point.
     */
    function POINT_3() external view returns (uint48 point);
}
