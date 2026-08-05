// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAccount} from "../IAccount.sol";

/**
 * @title ISecuritizeNoticeAccount
 * @notice Interface for Securitize redemption notices settled offchain.
 */
interface ISecuritizeNoticeAccount is IAccount {
    /* EVENTS */

    /**
     * @notice Emitted when tokens are submitted to the Securitize redemption wallet.
     * @param tokenAmount The submitted token-to-redeem amount.
     * @param assets The frozen expected settlement amount.
     * @param expiry The timestamp after which an unpaid residual is written off.
     */
    event RequestRedeem(uint256 tokenAmount, uint256 assets, uint48 expiry);

    /**
     * @notice Emitted when newly received settlement assets reduce the receivable.
     * @param assets The reconciled settlement amount.
     * @param pendingAssets The remaining receivable.
     */
    event ReconcileSettlement(uint256 assets, uint256 pendingAssets);

    /**
     * @notice Emitted when an expired unpaid receivable is written off.
     * @param assets The written-off settlement amount.
     */
    event WriteOff(uint256 assets);

    /* FUNCTIONS */

    /**
     * @notice Returns the wallet receiving redemption notices.
     * @return redemptionWallet The Securitize platform-wallet address.
     */
    function REDEMPTION_WALLET() external view returns (address redemptionWallet);

    /**
     * @notice Returns the maximum time an unpaid receivable remains counted.
     * @return duration The settlement duration.
     */
    function SETTLEMENT_DURATION() external view returns (uint48 duration);

    /**
     * @notice Returns the unpaid frozen settlement value.
     * @return assets The pending vault-asset amount.
     */
    function pendingAssets() external view returns (uint256 assets);

    /**
     * @notice Returns the current receivable's write-off timestamp.
     * @return expiry The expiry timestamp, or zero when no receivable is pending.
     */
    function pendingExpiry() external view returns (uint48 expiry);
}
