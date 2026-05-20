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
     * @notice Raised when the configured subnetwork or operator is invalid.
     */
    error InvalidNetOrOp();

    /**
     * @notice Raised when the configured duration is invalid.
     */
    error InvalidDuration();

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
     * @param isBurnerHook Whether to call the vault burner hook on slashes.
     */
    struct InitParams {
        bytes32 subnetwork;
        address operator;
        uint48 duration;
        bool isBurnerHook;
    }

    /* EVENTS */

    /**
     * @notice Emitted when stake is slashed.
     * @param subnetwork Full identifier of the subnetwork.
     * @param operator Operator address.
     * @param amount Slashed amount.
     */
    event Slash(bytes32 indexed subnetwork, address indexed operator, uint256 amount);

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
     * @notice Get the cumulative slashed amount.
     * @return amount Slashed amount.
     */
    function slashed() external view returns (uint256 amount);

    /**
     * @notice Get the latest slash timestamp.
     * @return timestamp Slash timestamp.
     */
    function slashedAt() external view returns (uint48 timestamp);

    /**
     * @notice Get whether burner hook calls are enabled.
     * @return enabled Whether burner hook calls are enabled.
     */
    function isBurnerHook() external view returns (bool enabled);

    /**
     * @notice Get current guaranteed stake for the configured pair.
     * @param subnetwork Full identifier of the subnetwork.
     * @param operator Operator address.
     * @return amount Guaranteed stake.
     */
    function stake(bytes32 subnetwork, address operator) external view returns (uint256 amount);

    /**
     * @notice Get guaranteed stake for the configured pair at a timestamp.
     * @param subnetwork Full identifier of the subnetwork.
     * @param operator Operator address.
     * @param timestamp Timestamp to read.
     * @return amount Guaranteed stake.
     */
    function stakeAt(bytes32 subnetwork, address operator, uint48 timestamp, bytes calldata)
        external
        view
        returns (uint256 amount);

    /**
     * @notice Slash the configured pair.
     * @param subnetwork Full identifier of the subnetwork.
     * @param operator Operator address.
     * @param amount Maximum amount to slash.
     * @param captureTimestamp Capture timestamp, or zero for current stake.
     * @return slashedAmount Amount slashed.
     * @dev Only the network middleware can call this function.
     */
    function slash(bytes32 subnetwork, address operator, uint256 amount, uint48 captureTimestamp, bytes calldata)
        external
        returns (uint256 slashedAmount);
}
