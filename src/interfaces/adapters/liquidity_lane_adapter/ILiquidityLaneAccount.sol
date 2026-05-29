// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title ILiquidityLaneAccount
 * @notice Interface for token-specific liquidity lane redemption accounts.
 */
interface ILiquidityLaneAccount {
    /* FUNCTIONS */

    /**
     * @notice Submits token inventory for redemption and records the vault-funded principal spent.
     * @param amountToRedeem Token-to-redeem amount submitted.
     * @param amountSpent Vault asset principal spent for this redemption.
     */
    function redeem(uint256 amountToRedeem, uint256 amountSpent) external;

    /**
     * @notice Converts redemption proceeds into the vault asset.
     * @param redemptionToken Token currently held by the account.
     * @param converter Converter logic contract delegatecalled by the account.
     * @param amountIn Redemption-token amount to convert.
     * @param minAmountOut Minimum vault asset output.
     * @param data Converter-specific data.
     */
    function convertRedemption(
        address redemptionToken,
        address converter,
        uint256 amountIn,
        uint256 minAmountOut,
        bytes calldata data
    ) external;

    /**
     * @notice Realizes available principal and excess rewards.
     * @return principal Principal that should reduce outstanding vault-funded allocation.
     * @return rewards Excess rewards that should accrue to the vault.
     */
    function deallocate() external returns (uint256 principal, uint256 rewards);
}
