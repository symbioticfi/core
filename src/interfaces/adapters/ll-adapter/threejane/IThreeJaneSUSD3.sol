// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IThreeJaneSUSD3
 * @notice Interface for 3Jane sUSD3 cooldown redemption operations.
 */
interface IThreeJaneSUSD3 {
    /* FUNCTIONS */

    /**
     * @notice Returns the withdrawal asset.
     * @return asset The asset address.
     */
    function asset() external view returns (address asset);

    /**
     * @notice Returns the asset amount available for withdrawal by a user.
     * @param user The withdrawal owner.
     * @return assets The withdrawable USD3 amount.
     */
    function availableWithdrawLimit(address user) external view returns (uint256 assets);

    /**
     * @notice Returns shares converted to USD3 assets.
     * @param shares The sUSD3 share amount.
     * @return assets The USD3 asset amount.
     */
    function convertToAssets(uint256 shares) external view returns (uint256 assets);

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
        returns (uint48 cooldownEnd, uint48 windowEnd, uint256 shares);

    /**
     * @notice Returns the timestamp before which the user cannot start a cooldown.
     * @param user The lock owner.
     * @return timestamp The lock expiry timestamp.
     */
    function lockedUntil(address user) external view returns (uint48 timestamp);

    /**
     * @notice Starts a withdrawal cooldown for sUSD3 shares.
     * @param shares The sUSD3 share amount.
     */
    function startCooldown(uint256 shares) external;

    /**
     * @notice Withdraws USD3 assets during an active withdrawal window.
     * @param assets The USD3 amount to withdraw.
     * @param receiver The USD3 receiver.
     * @param owner The sUSD3 owner.
     * @return shares The sUSD3 shares burned.
     */
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);
}
