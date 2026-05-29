// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IMidasIssuer
 * @notice Interface for Midas liquidity lane issuers.
 */
interface IMidasIssuer {
    /* FUNCTIONS */

    /**
     * @notice Returns the token submitted to Midas for redemption.
     * @return tokenToRedeem The token-to-redeem address.
     */
    function TOKEN_TO_REDEEM() external view returns (address tokenToRedeem);

    /**
     * @notice Returns the preferred output asset.
     * @return asset The asset address.
     */
    function ASSET() external view returns (address asset);

    /**
     * @notice Returns the fallback redemption token when `ASSET` is not configured in Midas.
     * @return redemptionToken The fallback redemption token.
     */
    function REDEMPTION_TOKEN() external view returns (address redemptionToken);

    /**
     * @notice Returns the Midas redemption vault.
     * @return redemptionVault The Midas redemption vault.
     */
    function REDEMPTION_VAULT() external view returns (address redemptionVault);

    /**
     * @notice Returns the token-to-redeem inventory held by the issuer.
     * @return assets The held token-to-redeem amount.
     */
    function totalAssets() external view returns (uint256 assets);

    /**
     * @notice Submits held token-to-redeem inventory to Midas.
     * @return assets The submitted token-to-redeem amount.
     */
    function redeem() external returns (uint256 assets);
}
