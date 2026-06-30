// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IThreeFWhitelist
 * @notice Minimal 3F request whitelist interface.
 */
interface IThreeFWhitelist {
    /**
     * @notice Request whitelist status.
     */
    enum WhitelistStatus {
        NotWhitelisted,
        Whitelisted,
        PausedNotWhitelisted,
        PausedWhitelisted
    }

    /**
     * @notice Returns request whitelist status.
     * @param account Account to query.
     * @return status Whitelist status.
     */
    function isWhitelisted(address account) external view returns (WhitelistStatus status);
}
