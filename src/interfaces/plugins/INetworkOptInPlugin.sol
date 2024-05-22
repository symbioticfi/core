// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IPlugin} from "src/interfaces/base/IPlugin.sol";

interface INetworkOptInPlugin is IPlugin {
    error NotWhereEntity();
    error AlreadyOptedIn();
    error NotOptedIn();

    /**
     * @notice Emitted when network opts in to "where" entity.
     * @param network address of the network which opted in
     * @param resolver address of the resolver
     * @param where address of the entity where network opted in to
     */
    event OptIn(address indexed network, address indexed resolver, address indexed where);

    /**
     * @notice Emitted when network opts out from "where" entity.
     * @param network address of the network which opted out
     * @param resolver address of the resolver
     * @param where address of the entity where network opted out from
     */
    event OptOut(address indexed network, address indexed resolver, address indexed where);

    /**
     * @notice Get the address of the registry where to opt in.
     * @return address of the "where" registry
     */
    function WHERE_REGISTRY() external view returns (address);

    /**
     * @notice Check if network is opted-in to "where" entity.
     * @param network address of the network which can opt-in
     * @param resolver address of the resolver
     * @param where address of the entity to opt-in
     */
    function isOptedIn(address network, address resolver, address where) external view returns (bool);

    /**
     * @notice Get the timestamp of the last opt-out of network from "where" entity.
     * @param network address of the network which can opt-out
     * @param resolver address of the resolver
     * @param where address of the entity to opt-out
     */
    function lastOptOut(address network, address resolver, address where) external view returns (uint48);

    /**
     * @notice Opt-in a calling network to a particular "where" entity.
     * @param resolver address of the resolver
     * @param where address of the entity to opt-in
     */
    function optIn(address resolver, address where) external;

    /**
     * @notice Opt-out a calling network from a particular "where" entity.
     * @param resolver address of the resolver
     * @param where address of the entity to opt-out
     */
    function optOut(address resolver, address where) external;
}
