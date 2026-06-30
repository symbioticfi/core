// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IAssetoManager
 * @notice Interface for Asseto RWA manager redemptions serviced off-chain.
 */
interface IAssetoManager {
    /* FUNCTIONS */

    /**
     * @notice Returns the managed RWA token.
     * @return token The RWA token address.
     */
    function rwa() external view returns (address token);

    /**
     * @notice Returns the token used for redemption settlement.
     * @return token The settlement token address.
     */
    function collateral() external view returns (address token);

    /**
     * @notice Returns the minimum off-chain redemption amount.
     * @return amount The minimum token amount.
     */
    function minimumRedemptionAmount() external view returns (uint256 amount);

    /**
     * @notice Returns the maximum off-chain redemption amount.
     * @return amount The maximum token amount.
     */
    function maximumRedemptionAmount() external view returns (uint256 amount);

    /**
     * @notice Returns the next redemption request counter.
     * @return counter The next redemption counter.
     */
    function redemptionRequestCounter() external view returns (uint256 counter);

    /**
     * @notice Requests a redemption whose settlement is serviced off-chain.
     * @param amountRWATokenToRedeem The RWA token amount to redeem.
     * @param offChainDestination The off-chain destination identifier.
     */
    function requestRedemptionServicedOffchain(uint256 amountRWATokenToRedeem, bytes32 offChainDestination) external;
}
