// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IInfiniFiUnwindingModule
 * @notice Interface for the infiniFi unwinding module holding in-progress unwinding positions.
 */
interface IInfiniFiUnwindingModule {
    /* FUNCTIONS */

    /**
     * @notice Returns the current iUSD value of an unwinding position.
     * @dev Keeps accruing rewards during unwinding and reflects slashing; 0 for unknown positions.
     * @param user The position owner.
     * @param startUnwindingTimestamp The position's start timestamp.
     * @return amount The position's iUSD amount.
     */
    function balanceOf(address user, uint256 startUnwindingTimestamp) external view returns (uint256 amount);
}
