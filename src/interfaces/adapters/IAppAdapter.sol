// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAdapter} from "./IAdapter.sol";
import {ICoWSwapConverter} from "./common/ICoWSwapConverter.sol";

import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";

uint256 constant BURNER_GAS_LIMIT = 150_000;
uint256 constant BURNER_RESERVE = 20_000;

/**
 * @title IAppAdapter
 * @notice Interface for a single app/network-operator guarantee adapter.
 */
interface IAppAdapter is IAdapter, ICoWSwapConverter {
    /* ERRORS */

    /**
     * @notice Raised when the burner gas is insufficient.
     */
    error InsufficientBurnerGas();

    /**
     * @notice Raised when a slash has no slashable stake.
     */
    error InsufficientSlash();

    /**
     * @notice Raised when the configured duration is invalid.
     */
    error InvalidDuration();

    /**
     * @notice Raised when the configured subnetwork or operator is invalid.
     */
    error InvalidNetOrOp();

    /**
     * @notice Raised when a slash needs a burner but the adapter has none.
     */
    error NoBurner();

    /**
     * @notice Raised when the caller is not the subnetwork middleware.
     */
    error NotNetworkMiddleware();

    /**
     * @notice Raised when the caller is neither the network nor its middleware.
     */
    error NotNetworkOrMiddleware();

    /* STRUCTS */

    /**
     * @notice Initialization parameters for the app adapter.
     * @param burner Burner hook target.
     * @param duration Stake checkpoint lookahead duration.
     * @param operator Operator address.
     * @param subnetwork Full identifier of the subnetwork.
     * @param converters Initial converters exempt from the prepared-request delay.
     */
    struct InitParams {
        address burner;
        uint48 duration;
        address operator;
        bytes32 subnetwork;
        address[] converters;
    }

    /**
     * @notice Stake for the configured pair.
     * @param initialStake Initial stake.
     * @param debt Debt.
     * @param slashed Slashed.
     */
    struct Stake {
        uint256 initialStake;
        Checkpoints.Trace256 debt;
        Checkpoints.Trace256 slashed;
    }

    /* EVENTS */

    /**
     * @notice Emitted when stake is slashed.
     * @param amount Slashed amount.
     */
    event Slash(uint256 amount);

    /**
     * @notice Emitted when slashable stake is released by the network.
     * @param amount Released amount.
     */
    event Release(uint256 amount);

    /**
     * @notice Emitted when the adapter is initialized.
     * @param params Initialization parameters.
     */
    event Initialize(InitParams params);

    /* FUNCTIONS */

    /**
     * @notice Returns the asset managed by the app adapter.
     * @return asset Asset address.
     */
    function asset() external view returns (address asset);

    /**
     * @notice Get the configured burner hook target.
     * @return burner Burner hook target.
     */
    function burner() external view returns (address burner);

    /**
     * @notice Get the configured stake checkpoint lookahead duration.
     * @return duration Stake checkpoint lookahead duration.
     */
    function duration() external view returns (uint48 duration);

    /**
     * @notice Get the configured operator.
     * @return operator Operator address.
     */
    function operator() external view returns (address operator);

    /**
     * @notice Get the configured subnetwork.
     * @return subnetwork Full identifier of the subnetwork.
     */
    function subnetwork() external view returns (bytes32 subnetwork);

    /**
     * @notice Get current slashable stake for the configured pair.
     * @return amount Slashable stake.
     */
    function slashable() external view returns (uint256 amount);

    /**
     * @notice Get current guaranteed stake for the configured pair.
     * @return amount Guaranteed stake.
     */
    function stake() external view returns (uint256 amount);

    /**
     * @notice Get guaranteed stake for the configured pair at a timestamp.
     * @param timestamp Timestamp to read.
     * @return amount Guaranteed stake.
     */
    function stakeAt(uint48 timestamp) external view returns (uint256 amount);

    /**
     * @notice Transfer reward assets from the caller to the adapter.
     * @param token Reward token to transfer.
     * @param amount Amount of assets to transfer.
     */
    function reward(address token, uint256 amount) external;

    /**
     * @notice Release the configured pair's slashable stake.
     * @param amount Maximum amount to release.
     * @dev Only the configured network or its middleware can call this function.
     */
    function release(uint256 amount) external;

    /**
     * @notice Slash the configured pair.
     * @param amount Maximum amount to slash.
     * @dev Only the configured network middleware can call this function.
     */
    function slash(uint256 amount) external;
}
