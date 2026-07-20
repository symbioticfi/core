// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IThreeJaneSUSD3
 * @notice Interface for 3Jane sUSD3 cooldown redemption operations.
 */
interface IThreeJaneSUSD3 {
    /* FUNCTIONS */

    /**
     * @notice Returns the active cooldown status for a user.
     * @param user The cooldown owner.
     * @return cooldownEnd The timestamp when the cooldown ends.
     * @return windowEnd The timestamp when the withdrawal window closes.
     * @return shares The sUSD3 shares currently in cooldown.
     */
    function getCooldownStatus(address user)
        external
        view
        returns (uint256 cooldownEnd, uint256 windowEnd, uint256 shares);

    /**
     * @notice Starts a withdrawal cooldown for sUSD3 shares.
     * @param shares The sUSD3 share amount.
     */
    function startCooldown(uint256 shares) external;
}
