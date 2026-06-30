// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IRewards
 * @notice Interface for the Rewards contract.
 */
interface IRewards {
    function distributeDonationRewards(address vault, uint256 amount) external;
}
