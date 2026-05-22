// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAdapter} from "./IAdapter.sol";

/**
 * @title IAppAdapter
 * @notice Interface for a single app/network-operator guarantee adapter.
 */
interface IAppAdapter is IAdapter {
    /* ERRORS */

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
     * @notice Raised when a slash needs a burner but the vault has none.
     */
    error NoBurner();

    /**
     * @notice Raised when the caller is not the subnetwork middleware.
     */
    error NotNetworkMiddleware();

    /* STRUCTS */

    /**
     * @notice Initialization parameters for the app adapter.
     * @param subnetwork Full identifier of the subnetwork.
     * @param operator Operator address.
     * @param duration Stake checkpoint lookahead duration.
     */
    struct InitParams {
        bytes32 subnetwork;
        address operator;
        uint48 duration;
    }

    /* EVENTS */

    /**
     * @notice Emitted when stake is slashed.
     * @param amount Slashed amount.
     */
    event Slash(uint256 amount);

    /**
     * @notice Emitted when the adapter is initialized.
     * @param params Initialization parameters.
     */
    event Initialize(InitParams params);

    /* FUNCTIONS */

    /**
     * @notice Get the configured subnetwork.
     * @return subnetwork Full identifier of the subnetwork.
     */
    function subnetwork() external view returns (bytes32 subnetwork);

    /**
     * @notice Get the configured operator.
     * @return operator Operator address.
     */
    function operator() external view returns (address operator);

    /**
     * @notice Get the configured stake checkpoint lookahead duration.
     * @return duration Stake checkpoint lookahead duration.
     */
    function duration() external view returns (uint48 duration);

    /**
     * @notice Get current guaranteed stake for the configured pair.
     * @return amount Guaranteed stake.
     */
    function stake() external view returns (uint256 amount);

    /**
     * @notice Get current slashable stake for the configured pair.
     * @return amount Slashable stake.
     */
    function slashable() external view returns (uint256 amount);

    /**
     * @notice Get guaranteed stake for the configured pair at a timestamp.
     * @param timestamp Timestamp to read.
     * @param hints Optional lookup hints.
     * @return amount Guaranteed stake.
     */
    function stakeAt(uint48 timestamp, bytes calldata hints) external view returns (uint256 amount);

    /**
     * @notice Get slashable stake for the configured pair at a timestamp.
     * @param timestamp Timestamp to read.
     * @param hints Optional lookup hints.
     * @return amount Slashable stake.
     */
    function slashableAt(uint48 timestamp, bytes calldata hints) external view returns (uint256 amount);

    /**
     * @notice Slash the configured pair.
     * @param amount Maximum amount to slash.
     * @return slashedAmount Amount slashed.
     * @dev Only the configured network middleware can call this function.
     */
    function slash(uint256 amount) external returns (uint256 slashedAmount);
}
