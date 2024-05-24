// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface INetworkOptInService {
    error AlreadyOptedIn();
    error NotOptedIn();
    error NotWhereEntity();
    error NotNetwork();

    /**
     * @notice Emitted when a network opts-in to a "where" entity.
     * @param network address of the network that opted-in
     * @param resolver address of the resolver
     * @param where address of the entity where the network opted-in to
     */
    event OptIn(address indexed network, address indexed resolver, address indexed where);

    /**
     * @notice Emitted when a network opts out from a "where" entity.
     * @param network address of the network that opted out
     * @param resolver address of the resolver
     * @param where address of the entity where the network opted out from
     */
    event OptOut(address indexed network, address indexed resolver, address indexed where);

    /**
     * @notice Get the network registry's address.
     * @return address of the network registry
     */
    function NETWORK_REGISTRY() external view returns (address);

    /**
     * @notice Get the address of the registry where to opt-in.
     * @return address of the "where" registry
     */
    function WHERE_REGISTRY() external view returns (address);

    /**
     * @notice Check if a given network is opted-in to a particular "where" entity.
     * @param network address of the network
     * @param resolver address of the resolver
     * @param where address of the entity to opt-in to
     */
    function isOptedIn(address network, address resolver, address where) external view returns (bool);

    /**
     * @notice Get the timestamp of the last opt-out of a given network from a particular "where" entity.
     * @param network address of the network
     * @param resolver address of the resolver
     * @param where address of the entity to opt-out from
     */
    function lastOptOut(address network, address resolver, address where) external view returns (uint48);

    /**
     * @notice Check if a given network was opted-in to a particular "where" entity after the edge timestamp inclusively.
     * @param network address of the network
     * @param where address of the entity to opt-in to
     * @param edgeTimestamp timestamp to check if the network was opted-in after
     */
    function wasOptedIn(
        address network,
        address resolver,
        address where,
        uint256 edgeTimestamp
    ) external view returns (bool);

    /**
     * @notice Opt-in a calling network to a particular "where" entity.
     * @param resolver address of the resolver
     * @param where address of the entity to opt-in to
     */
    function optIn(address resolver, address where) external;

    /**
     * @notice Opt-out a calling network from a particular "where" entity.
     * @param resolver address of the resolver
     * @param where address of the entity to opt-out from
     */
    function optOut(address resolver, address where) external;
}
