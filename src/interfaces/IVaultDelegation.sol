// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IVaultStorage} from "./IVaultStorage.sol";

interface IVaultDelegation is IVaultStorage {
    error NotNetwork();
    error NotOperator();
    error NetworkAlreadyOptedIn();
    error InvalidMaxNetworkLimit();
    error NetworkNotOptedIn();
    error OperatorAlreadyOptedIn();
    error ExceedsMaxNetworkLimit();
    error OperatorNotOptedIn();
    error AlreadySet();
    error NoDepositWhitelist();

    /**
     * @notice Emitted when a network opts in.
     * @param network network which opted in
     * @param resolver resolver who can veto the the network's slash requests
     */
    event OptInNetwork(address indexed network, address indexed resolver);

    /**
     * @notice Emitted when a network opts out.
     * @param network network which opted out
     * @param resolver resolver who could veto the the network's slash requests
     */
    event OptOutNetwork(address indexed network, address indexed resolver);

    /**
     * @notice Emitted when an operator opts in.
     * @param operator operator who opted in
     */
    event OptInOperator(address indexed operator);

    /**
     * @notice Emitted when an operator opts out.
     * @param operator operator who opted out
     */
    event OptOutOperator(address indexed operator);

    /**
     * @notice Emitted when a metadata URL is set.
     * @param metadataURL metadata URL of the vault
     */
    event SetMetadataURL(string metadataURL);

    /**
     * @notice Emitted when an admin fee is set.
     * @param adminFee admin fee
     */
    event SetAdminFee(uint256 adminFee);

    /**
     * @notice Emitted when deposit whitelist status is set.
     * @param depositWhitelist enable/disable deposit whitelist
     */
    event SetDepositWhitelist(bool depositWhitelist);

    /**
     * @notice Emitted when a depositor whitelist status is set.
     * @param account account for which the whitelist status is set
     * @param value whitelist status
     */
    event SetDepositorWhitelistStatus(address indexed account, bool value);

    /**
     * @notice Emitted when a network limit is set.
     * @param network network for which the limit is set
     * @param resolver resolver for which the limit is set
     * @param amount amount of the collateral that can be slashed
     */
    event SetNetworkLimit(address indexed network, address indexed resolver, uint256 amount);

    /**
     * @notice Emitted when an operator limit is set.
     * @param operator operator for which the limit is set
     * @param network network for which the limit is set
     * @param amount amount of the collateral that can be slashed
     */
    event SetOperatorLimit(address indexed operator, address indexed network, uint256 amount);

    /**
     * @notice Get if a given network-resolver pair is opted in.
     * @return if the network-resolver pair is opted in
     */
    function isNetworkOptedIn(address network, address resolver) external view returns (bool);

    /**
     * @notice Get if a given operator is opted in.
     * @return if the operator is opted in
     */
    function isOperatorOptedIn(address operator) external view returns (bool);

    /**
     * @notice Get a network limit for a particular network and resolver.
     * @param network address of the network
     * @param resolver address of the resolver
     * @return network limit
     */
    function networkLimit(address network, address resolver) external view returns (uint256);

    /**
     * @notice Get an operator limit for a particular operator and network.
     * @param operator address of the operator
     * @param network address of the network
     * @return operator limit
     */
    function operatorLimit(address operator, address network) external view returns (uint256);

    /**
     * @notice Opt in a network with a given resolver.
     * @param resolver address of the resolver
     * @param maxNetworkLimit maximum network limit
     * @dev Only network can call this function.
     */
    function optInNetwork(address resolver, uint256 maxNetworkLimit) external;

    /**
     * @notice Opt out a network with a given resolver.
     * @param resolver address of the resolver
     * @dev Only network can call this function.
     */
    function optOutNetwork(address resolver) external;

    /**
     * @notice Opt in an operator.
     * @dev Only operator can call this function.
     */
    function optInOperator() external;

    /**
     * @notice Opt out an operator.
     * @dev Only operator can call this function.
     */
    function optOutOperator() external;

    /**
     * @notice Set a new metadata URL for this vault.
     * @param metadataURL metadata URL of the vault
     * The metadata should contain: name, description, external_url, image.
     * @dev Only owner can call this function.
     */
    function setMetadataURL(string calldata metadataURL) external;

    /**
     * @notice Set an admin fee.
     * @param adminFee admin fee (up to ADMIN_FEE_BASE inclusively)
     * @dev Only ADMIN_FEE_SET_ROLE holder can call this function.
     */
    function setAdminFee(uint256 adminFee) external;

    /**
     * @notice Enable/disable deposit whitelist.
     * @param status enable/disable deposit whitelist
     * @dev Only DEPOSIT_WHITELIST_SET_ROLE holder can call this function.
     */
    function setDepositWhitelist(bool status) external;

    /**
     * @notice Set a depositor whitelist status.
     * @param account account for which the whitelist status is set
     * @param status whitelist status
     * @dev Only DEPOSITOR_WHITELIST_ROLE holder can call this function.
     */
    function setDepositorWhitelistStatus(address account, bool status) external;

    /**
     * @notice Set a network limit for a particular network and resolver.
     * @param network address of the network
     * @param resolver address of the resolver
     * @param amount maximum amount of the collateral that can be slashed
     * @dev Only NETWORK_LIMIT_SET_ROLE holder can call this function.
     */
    function setNetworkLimit(address network, address resolver, uint256 amount) external;

    /**
     * @notice Set an operator limit for a particular operator and network.
     * @param operator address of the operator
     * @param network address of the network
     * @param amount maximum amount of the collateral that can be slashed
     * @dev Only OPERATOR_LIMIT_SET_ROLE holder can call this function.
     */
    function setOperatorLimit(address operator, address network, uint256 amount) external;
}
