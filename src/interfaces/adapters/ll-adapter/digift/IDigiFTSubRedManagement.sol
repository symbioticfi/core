// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IDigiFTSubRedManagement
 * @notice Interface for DigiFT subscription and redemption management.
 */
interface IDigiFTSubRedManagement {
    /* FUNCTIONS */

    /**
     * @notice Requests a normal redemption of a DigiFT security token into a currency token.
     * @param stToken The DigiFT security token to redeem.
     * @param currencyToken The settlement currency token.
     * @param quantity The amount of security token to redeem.
     * @param deadline The transaction deadline accepted by the manager.
     */
    function redeem(address stToken, address currencyToken, uint256 quantity, uint256 deadline) external;
}
