// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IPlugin} from "src/interfaces/base/IPlugin.sol";

interface IOperatorOptInPlugin is IPlugin {
    error NotWhereEntity();
    error AlreadyOptedIn();
    error NotOptedIn();

    /**
     * @notice Emitted when operator opts in to "where" entity.
     * @param operator address of the operator which opted in
     * @param where address of the entity where operator opted in to
     */
    event OptIn(address indexed operator, address indexed where);

    /**
     * @notice Emitted when operator opts out from "where" entity.
     * @param operator address of the operator which opted out
     * @param where address of the entity where operator opted out from
     */
    event OptOut(address indexed operator, address indexed where);

    /**
     * @notice Get the address of the registry where to opt in.
     * @return address of the "where" registry
     */
    function WHERE_REGISTRY() external view returns (address);

    /**
     * @notice Check if operator is opted-in to "where" entity.
     * @param operator address of the operator which can opt-in
     * @param where address of the entity to opt-in
     */
    function isOptedIn(address operator, address where) external view returns (bool);

    /**
     * @notice Get the timestamp of the last opt-out of operator from "where" entity.
     * @param operator address of the operator which can opt-out
     * @param where address of the entity to opt-out
     */
    function lastOptOut(address operator, address where) external view returns (uint48);

    /**
     * @notice Opt-in a calling operator to a particular "where" entity.
     * @param where address of the entity to opt-in
     */
    function optIn(address where) external;

    /**
     * @notice Opt-out a calling operator from a particular "where" entity.
     * @param where address of the entity to opt-out
     */
    function optOut(address where) external;
}
