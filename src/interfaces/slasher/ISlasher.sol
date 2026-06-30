// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IBaseSlasher} from "./IBaseSlasher.sol";

uint64 constant SLASHER_TYPE = 0;

/**
 * @title ISlasher
 * @notice Interface for the Slasher contract.
 */
interface ISlasher is IBaseSlasher {
    error InsufficientSlash();
    error InvalidCaptureTimestamp();

    /**
     * @notice Initial parameters needed for a slasher deployment.
     * @param baseParams Base parameters for slashers' deployment.
     */
    struct InitParams {
        IBaseSlasher.BaseParams baseParams;
    }

    /**
     * @notice Hints for a slash.
     * @param slashableStakeHints Hints for the slashable stake checkpoints.
     */
    struct SlashHints {
        bytes slashableStakeHints;
    }

    /**
     * @notice Extra data for the delegator.
     * @param slashableStake Amount of the slashable stake before the slash (cache).
     * @param stakeAt Amount of the stake at the capture time (cache).
     */
    struct DelegatorData {
        uint256 slashableStake;
        uint256 stakeAt;
    }

    /**
     * @notice Emitted when a slash is performed.
     * @param subnetwork Subnetwork that requested the slash.
     * @param operator Operator that is slashed.
     * @param slashedAmount Virtual amount of the collateral slashed.
     * @param captureTimestamp Time point when the stake was captured.
     */
    event Slash(bytes32 indexed subnetwork, address indexed operator, uint256 slashedAmount, uint48 captureTimestamp);

    /**
     * @notice Perform a slash using a subnetwork for a particular operator by a given amount using hints.
     * @param subnetwork Full identifier of the subnetwork (address of the network concatenated with the uint96 identifier).
     * @param operator Address of the operator.
     * @param amount Maximum amount of the collateral to be slashed.
     * @param captureTimestamp Time point when the stake was captured.
     * @param hints Hints for checkpoints' indexes.
     * @return slashedAmount Virtual amount of the collateral slashed.
     * @dev Only a network middleware can call this function.
     */
    function slash(bytes32 subnetwork, address operator, uint256 amount, uint48 captureTimestamp, bytes calldata hints)
        external
        returns (uint256 slashedAmount);
}
