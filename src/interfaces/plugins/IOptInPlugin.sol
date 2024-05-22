// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IPlugin} from "src/interfaces/base/IPlugin.sol";

interface IOptInPlugin is IPlugin {
    error NotWhereEntity();
    error AlreadyOptedIn();
    error NotOptedIn();

    /**
     * @notice Emitted when "who" entity opts in to "where" entity.
     * @param who address of the entity who opted in
     * @param where address of the entity where "who" entity opted in to
     */
    event OptIn(address indexed who, address indexed where);

    /**
     * @notice Emitted when "who" entity opts out from "where" entity.
     * @param who address of the entity who opted out
     * @param where address of the entity where "who" entity opted out from
     */
    event OptOut(address indexed who, address indexed where);

    /**
     * @notice Get the address of the registry where to opt in.
     * @return address of the "where" registry
     */
    function WHERE_REGISTRY() external view returns (address);

    /**
     * @notice Check if "who" entity is opted-in to "where" entity.
     * @param who address of the entity who can opt-in
     * @param where address of the entity to opt-in
     */
    function isOptedIn(address who, address where) external view returns (bool);

    /**
     * @notice Get the timestamp of the last opt-out of "who" entity from "where" entity.
     * @param who address of the entity who can opt-out
     * @param where address of the entity to opt-out
     */
    function lastOptOut(address who, address where) external view returns (uint48);

    /**
     * @notice Opt-in a calling "who" entity to a particular "where" entity.
     * @param where address of the entity to opt-in
     */
    function optIn(address where) external;

    /**
     * @notice Opt-out a calling "who" entity from a particular "where" entity.
     * @param where address of the entity to opt-out
     */
    function optOut(address where) external;
}
