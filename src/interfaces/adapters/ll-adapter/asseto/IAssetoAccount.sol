// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ICooldownAccount} from "../ICooldownAccount.sol";
import {ICutoffAccount} from "../ICutoffAccount.sol";

/**
 * @title IAssetoAccount
 * @notice Interface for Asseto off-chain settlement accounts.
 */
interface IAssetoAccount is ICooldownAccount, ICutoffAccount {
    /* ERRORS */

    /**
     * @notice Raised when the Asseto manager is not configured for the token-to-redeem.
     */
    error InvalidAsset();

    /* EVENTS */

    /**
     * @notice Emitted when a cutoff bucket's rate is frozen.
     * @param bucket The bucket index.
     * @param rate The frozen rate in the host's oracle precision.
     */
    event FreezeBucket(uint48 indexed bucket, uint256 rate);

    /* STRUCTS */

    /**
     * @notice Initialization parameters for an Asseto account clone.
     * @param vault The vault bound to the account.
     * @param adapter The adapter bound to the account.
     * @param offChainDestination The Asseto off-chain destination identifier.
     */
    struct InitParams {
        address vault;
        address adapter;
        bytes32 offChainDestination;
    }

    /* FUNCTIONS */

    /**
     * @notice Returns the delay between a cutoff and its pricing date.
     * @return valuationDelay The valuation delay.
     */
    function VALUATION_DELAY() external view returns (uint48 valuationDelay);

    /**
     * @notice Returns how long after the cutoff pending value is counted.
     * @return postCutoffWindow The post-cutoff window.
     */
    function POST_CUTOFF_WINDOW() external view returns (uint48 postCutoffWindow);

    /**
     * @notice Returns a cutoff bucket.
     * @param bucket The bucket index.
     * @return totalTokenToRedeem The cumulative token-to-redeem amount submitted to this bucket.
     * @return pendingTokenToRedeem The still-pending token-to-redeem amount in this bucket.
     * @return rate The frozen bucket rate.
     */
    function buckets(uint48 bucket)
        external
        view
        returns (uint256 totalTokenToRedeem, uint256 pendingTokenToRedeem, uint256 rate);

    /**
     * @notice Returns a pending cutoff entry by key.
     * @param key The pending redemption key.
     * @return amount The token-to-redeem amount pending.
     * @return bucket The assigned cutoff bucket index.
     */
    function pendingCutoffs(uint256 key) external view returns (uint256 amount, uint48 bucket);

    /**
     * @notice Returns the Asseto manager contract.
     * @return manager The manager address.
     */
    function MANAGER() external view returns (address manager);

    /**
     * @notice Returns the Asseto off-chain destination identifier.
     * @return destination The destination identifier.
     */
    function offChainDestination() external view returns (bytes32 destination);
}
