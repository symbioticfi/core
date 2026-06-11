// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IInfiniFiRedeemController
 * @notice Interface for the infiniFi redeem controller paying out iUSD redemptions.
 */
interface IInfiniFiRedeemController {
    /* FUNCTIONS */

    /**
     * @notice Returns the asset token paid out by redemptions.
     * @return token The asset token.
     */
    function assetToken() external view returns (address token);

    /**
     * @notice Returns the redemption queue cursor bounds.
     * @dev Tickets at indices in `[begin, end)` are enqueued; a ticket is fully funded once `begin`
     *      passes its index.
     * @return begin The index of the queue's front ticket.
     * @return end The index after the queue's back ticket.
     */
    function queue() external view returns (uint128 begin, uint128 end);

    /**
     * @notice Returns the total iUSD currently enqueued and waiting to be funded.
     * @return amount The enqueued iUSD amount.
     */
    function totalEnqueuedRedemptions() external view returns (uint256 amount);

    /**
     * @notice Returns a recipient's funded-but-unclaimed redemption payout.
     * @param recipient The queue ticket beneficiary.
     * @return assets The claimable asset amount.
     */
    function userPendingClaims(address recipient) external view returns (uint256 assets);
}
