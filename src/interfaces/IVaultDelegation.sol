// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IVaultStorage} from "./IVaultStorage.sol";
import {IMigratableEntity} from "src/interfaces/base/IMigratableEntity.sol";

interface IVaultDelegation is IVaultStorage, IMigratableEntity {
    error InvalidEpochDuration();
    error InvalidSlashDuration();
    error InvalidAdminFee();
    error NotNetwork();
    error NotOperator();
    error NetworkNotOptedInVault();
    error ExceedsMaxNetworkLimit();
    error OperatorNotOptedInVault();
    error AlreadySet();
    error NoDepositWhitelist();

    /**
     * @notice Initial parameters needed for a vault deployment.
     * @param owner owner of the vault (can set metadata and enable/disable deposit whitelist)
     * The metadata should contain: name, description, external_url, image.
     * @param collateral underlying vault collateral
     * @param epochDuration duration of an vault epoch
     * @param vetoDuration duration of the veto period for a slash request
     * @param slashDuration duration of the slash period for a slash request (after veto period)
     * @param adminFee admin fee (up to ADMIN_FEE_BASE inclusively)
     * @param depositWhitelist enable/disable deposit whitelist
     */
    struct InitParams {
        address owner;
        address collateral;
        uint48 epochDuration;
        uint48 vetoDuration;
        uint48 slashDuration;
        uint256 adminFee;
        bool depositWhitelist;
    }

    /**
     * @notice Emitted when a maximum network limit is set.
     * @param network network for which the maximum limit is set
     * @param resolver resolver for which the maximum limit is set
     * @param amount maximum possible amount of the collateral that can be slashed
     */
    event SetMaxNetworkLimit(address indexed network, address indexed resolver, uint256 amount);

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
     * @notice Set a maximum network limit.
     * @param resolver address of the resolver
     * @param amount maximum amount of the collateral that can be slashed
     * @dev Only network can call this function.
     */
    function setMaxNetworkLimit(address resolver, uint256 amount) external;

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
