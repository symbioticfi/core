// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title ICutoffAccount
 * @notice Interface for accounts grouping non-instant redemption requests into cutoff buckets.
 */
interface ICutoffAccount {
    /* ERRORS */

    /**
     * @notice Raised when a cutoff bucket or timestamp is outside the supported schedule.
     */
    error InvalidCutoff();

    /**
     * @notice Raised when the live cutoff price is zero.
     */
    error InvalidCutoffPrice();

    /* FUNCTIONS */

    /**
     * @notice Returns the current cutoff bucket index.
     * @return bucket The current bucket index.
     */
    function currentBucket() external view returns (uint48 bucket);

    /**
     * @notice Returns the next cutoff timestamp.
     * @return timestamp The next cutoff timestamp.
     */
    function nextCutoff() external view returns (uint48 timestamp);

    /**
     * @notice Converts a timestamp to its cutoff bucket index.
     * @param timestamp The timestamp to convert.
     * @return bucket The bucket index.
     */
    function timestampToBucket(uint48 timestamp) external view returns (uint48 bucket);

    /**
     * @notice Converts a cutoff bucket index to its cutoff timestamp.
     * @param bucket The bucket index to convert.
     * @return timestamp The bucket cutoff timestamp.
     */
    function bucketToTimestamp(uint48 bucket) external view returns (uint48 timestamp);
}
