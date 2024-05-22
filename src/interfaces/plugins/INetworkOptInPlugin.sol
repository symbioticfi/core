// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IPlugin} from "src/interfaces/base/IPlugin.sol";

interface INetworkOptInPlugin is IPlugin {
    error NotNetwork();
    error OperatorAlreadyOptedIn();
    error OperatorNotOptedIn();

    /**
     * @notice Get the network registry address.
     * @return address of the registry
     */
    function NETWORK_REGISTRY() external view returns (address);

    /**
     * @notice Get if a given operator is opted-in to a particular network.
     * @param operator address of the operator
     * @param network address of the network
     * @return if the operator is opted-in
     */
    function isOperatorOptedIn(address operator, address network) external view returns (bool);

    /**
     * @notice Get the last timestamp when a given operator opted-out of a particular network.
     * @param operator address of the operator
     * @param network address of the network
     * @return timestamp when the operator opted-out
     */
    function lastOperatorOptOut(address operator, address network) external view returns (uint48);

    /**
     * @notice Opt-in a calling operator to a particular network.
     * @param network address of the network
     */
    function optIn(address network) external;

    /**
     * @notice Opt-out a calling operator from a particular network.
     * @param network address of the network
     */
    function optOut(address network) external;
}
