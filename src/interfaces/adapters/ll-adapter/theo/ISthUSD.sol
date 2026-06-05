// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title ISthUSD
 * @notice Interface for Theo sthUSD async redemption operations.
 */
interface ISthUSD {
    /* FUNCTIONS */

    /**
     * @notice Returns the thUSD asset backing this sthUSD vault.
     * @return asset The thUSD asset address.
     */
    function asset() external view returns (address asset);

    /**
     * @notice Returns the active redemption request for an owner.
     * @param owner The request owner.
     * @return assets The pending thUSD asset amount.
     * @return shares The pending sthUSD share amount.
     * @return claimableTimestamp The timestamp when the request can be claimed.
     */
    function currentRedeemRequest(address owner)
        external
        view
        returns (uint256 assets, uint256 shares, uint256 claimableTimestamp);

    /**
     * @notice Initiates an async redemption request.
     * @param shares The sthUSD share amount.
     * @param owner The sthUSD owner.
     */
    function initiateRedeem(uint256 shares, address owner) external;

    /**
     * @notice Claims matured thUSD assets by redeeming request shares.
     * @param shares The request share amount to claim.
     * @param receiver The thUSD receiver.
     * @param owner The request owner.
     * @return assets The claimed thUSD amount.
     */
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
}
