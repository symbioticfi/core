// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBasePlugin {
    /**
     * @notice Trigger a push (returning owed amount) of the collateral.
     * @param amount amount of the collateral to push
     * @return if the push was successful
     */
    function triggerPush(uint256 amount) external returns (bool);
}
