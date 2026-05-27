// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAppAdapter} from "./IAppAdapter.sol";

/**
 * @title IRestakingAppAdapter
 * @notice Interface for an app adapter that reports guarantees in a restaking token's base asset.
 */
interface IRestakingAppAdapter is IAppAdapter {
    /* ERRORS */

    /**
     * @notice Raised when the configured base asset does not match the vault asset wrapper.
     */
    error InvalidBaseAsset();

    /* STRUCTS */

    /**
     * @notice Initialization parameters for the restaking app adapter.
     * @param baseAsset Base asset of the vault asset wrapper.
     * @param burner Burner hook target.
     * @param duration Stake checkpoint lookahead duration.
     * @param operator Operator address.
     * @param subnetwork Full identifier of the subnetwork.
     */
    struct RestakingInitParams {
        address baseAsset;
        address burner;
        uint48 duration;
        address operator;
        bytes32 subnetwork;
    }

    /* FUNCTIONS */

    /**
     * @notice Returns the base asset used for rewards, slashing, and stake views.
     * @return asset Base asset address.
     */
    function baseAsset() external view returns (address asset);
}
