// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface INetworkOptInService {
    error AlreadyOptedIn();
    error NotNetwork();
    error NotOptedIn();
    error NotVault();

    /**
     * @notice Emitted when a network opts into a vault.
     * @param network address of the network
     * @param resolver address of the resolver
     * @param vault address of the vault
     */
    event OptIn(address indexed network, address indexed resolver, address indexed vault);

    /**
     * @notice Emitted when a network opts out from a vault.
     * @param network address of the network
     * @param resolver address of the resolver
     * @param vault address of the vault
     */
    event OptOut(address indexed network, address indexed resolver, address indexed vault);

    /**
     * @notice Get the network registry's address.
     * @return address of the network registry
     */
    function NETWORK_REGISTRY() external view returns (address);

    /**
     * @notice Get the vault registry's address.
     * @return address of the vault registry
     */
    function VAULT_REGISTRY() external view returns (address);

    /**
     * @notice Check if a given network is opted-in to a particular vault.
     * @param network address of the network
     * @param resolver address of the resolver
     * @param vault address of the vault
     */
    function isOptedIn(address network, address resolver, address vault) external view returns (bool);

    /**
     * @notice Get the timestamp of the last opt-out of a given network from a particular vault.
     * @param network address of the network
     * @param resolver address of the resolver
     * @param vault address of the vault
     */
    function lastOptOut(address network, address resolver, address vault) external view returns (uint48);

    /**
     * @notice Check if a given network was opted-in to a particular vault after a given timestamp (inclusively).
     * @param network address of the network
     * @param vault address of the vault
     * @param timestamp time point to check if the network was opted-in after
     */
    function wasOptedInAfter(
        address network,
        address resolver,
        address vault,
        uint48 timestamp
    ) external view returns (bool);

    /**
     * @notice Opt-in a calling network to a particular vault.
     * @param resolver address of the resolver
     * @param vault address of the vault
     */
    function optIn(address resolver, address vault) external;

    /**
     * @notice Opt-out a calling network from a particular vault.
     * @param resolver address of the resolver
     * @param vault address of the vault
     */
    function optOut(address resolver, address vault) external;
}
