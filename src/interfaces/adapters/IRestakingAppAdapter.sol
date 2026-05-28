// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAppAdapter} from "./IAppAdapter.sol";

uint256 constant MAX_DEPTH = 5;

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

    /* FUNCTIONS */

    /**
     * @notice Returns a vault in the restaking asset chain.
     * @param index Underlying vault index.
     * @return vault Underlying vault address.
     */
    function underlyingVaults(uint256 index) external view returns (address vault);

    /**
     * @notice Synchronizes pending slashed withdrawal requests.
     */
    function syncSlash() external;
}
