// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IDelegator {
    /**
     * @notice Get a version of the delegator (different versions mean different interfaces).
     * @return version of the delegator
     * @dev Must return 1 for this one.
     */
    function VERSION() external view returns (uint64);

    /**
     * @notice Get the vault's address.
     * @return address of the vault
     */
    function vault() external view returns (address);
    
    /**
     * @notice Get a network-resolver limit for a particular network and resolver in `duration` seconds.
     * @param network address of the network
     * @param resolver address of the resolver
     * @param duration duration to get the network-resolver limit in
     * @return network-resolver limit in `duration` seconds
     */
    function networkResolverLimitIn(
        address network,
        address resolver,
        uint48 duration
    ) external view returns (uint256);

    /**
     * @notice Get a network-resolver limit for a particular network and resolver.
     * @param network address of the network
     * @param resolver address of the resolver
     * @return network-resolver limit
     */
    function networkResolverLimit(address network, address resolver) external view returns (uint256);

    /**
     * @notice Get an operator-network limit for a particular operator and network in `duration` seconds.
     * @param operator address of the operator
     * @param network address of the network
     * @param duration duration to get the operator-network limit in
     * @return operator-network limit in `duration` seconds
     */
    function operatorNetworkLimitIn(
        address operator,
        address network,
        uint48 duration
    ) external view returns (uint256);

    /**
     * @notice Get an operator-network limit for a particular operator and network.
     * @param operator address of the operator
     * @param network address of the network
     * @return operator-network limit
     */
    function operatorNetworkLimit(address operator, address network) external view returns (uint256);

    /**
     * @notice Slashing callback for limits decreasing.
     * @param slashedAmount a
     */
    function onSlash(
        address network,
        address resolver,
        address operator,
        uint256 slashedAmount
    ) external;
}
