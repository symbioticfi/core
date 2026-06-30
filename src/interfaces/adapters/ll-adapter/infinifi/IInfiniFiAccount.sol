// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ICooldownAccount} from "../ICooldownAccount.sol";

/**
 * @title IInfiniFiAccount
 * @notice Interface for infiniFi liquidity lane accounts.
 */
interface IInfiniFiAccount is ICooldownAccount {
    /* FUNCTIONS */

    /**
     * @notice Returns the infiniFi gateway.
     * @return gateway The gateway address.
     */
    function GATEWAY() external view returns (address gateway);

    /**
     * @notice Returns the infiniFi unwinding module.
     * @return unwindingModule The unwinding module address.
     */
    function UNWINDING_MODULE() external view returns (address unwindingModule);

    /**
     * @notice Returns the iUSD receipt token paid out by completed unwindings.
     * @return iusd The iUSD address.
     */
    function IUSD() external view returns (address iusd);

    /**
     * @notice Returns the unwinding duration of the locked bucket in epochs.
     * @return unwindingEpochs The unwinding epochs count.
     */
    function UNWINDING_EPOCHS() external view returns (uint32 unwindingEpochs);

    /**
     * @notice Returns an unwinding position start timestamp by index.
     * @param index The position index.
     * @return timestamp The unwinding start timestamp keying the position.
     */
    function unwindingTimestamps(uint256 index) external view returns (uint48 timestamp);
}
