// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAppAdapter} from "./IAppAdapter.sol";

uint256 constant MAX_DEPTH = 4;
uint256 constant MAX_CLAIMS = 5;

/**
 * @title IRestakingAppAdapter
 * @notice Interface for an app adapter that reports guarantees in a restaking token's base asset.
 */
interface IRestakingAppAdapter is IAppAdapter {
    /* ERRORS */

    /**
     * @notice Raised when the configured asset does not match the vault asset chain.
     */
    error InvalidAsset();

    /**
     * @notice Raised when the configured base asset does not match the vault asset wrapper.
     */
    error InvalidBaseAsset();

    /**
     * @notice Raised when the configured asset is not a restaking wrapper.
     */
    error NotRestaking();

    /**
     * @notice Raised when the operation is not supported for the restaking adapter.
     */
    error Unsupported();

    /* STRUCTS */

    /**
     * @notice Initialization parameters for the restaking app adapter.
     * @param asset Base asset of the vault asset wrapper chain.
     * @param initParams App adapter initialization parameters.
     */
    struct RestakingInitParams {
        address asset;
        IAppAdapter.InitParams initParams;
    }

    /**
     * @notice Pending slash withdrawal requests for one underlying vault.
     * @param firstUnclaimed Index of the first tracked withdrawal NFT that has not been fully claimed yet.
     * @param tokenIds Withdrawal queue NFT ids created while unwinding slashed restaking exposure.
     */
    struct WithdrawalRequests {
        uint256 firstUnclaimed;
        uint64[] tokenIds;
    }

    /* FUNCTIONS */

    /**
     * @notice Returns a vault in the restaking asset chain.
     * @param index Underlying vault index.
     * @return vault Underlying vault address.
     */
    function underlyingVaults(uint256 index) external view returns (address vault);

    /**
     * @notice Returns the pending slash withdrawal claim cursor for an underlying vault.
     * @param vault Underlying vault whose withdrawal queue requests are tracked.
     * @return firstUnclaimed Index of the first tracked withdrawal NFT that has not been fully claimed yet.
     */
    function withdrawalRequests(address vault) external view returns (uint256 firstUnclaimed);

    /**
     * @notice Returns whether there are pending slashed withdrawal requests to sync.
     * @return status Whether there are pending slashed withdrawal requests.
     */
    function isUnsyncedSlash() external view returns (bool status);

    /**
     * @notice Synchronizes held base asset rewards into the restaking vault asset.
     */
    function syncReward() external;

    /**
     * @notice Synchronizes pending slashed withdrawal requests.
     */
    function syncSlash() external;

    /**
     * @notice Slash the configured pair.
     * @param amount Maximum amount to slash, denominated in the configured base asset.
     * @dev Only the configured network middleware can call this function.
     * @dev Restaking slash synchronizes pending slash withdrawals and can request redemptions from underlying
     *      withdrawal queues before applying slash accounting; a reverting underlying queue can revert the slash.
     */
    function slash(uint256 amount) external override;
}
