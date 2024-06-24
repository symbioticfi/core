// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IStakerRewardsDistributor} from "src/interfaces/stakerRewardsDistributor/IStakerRewardsDistributor.sol";

interface IDefaultStakerRewardsDistributor is IStakerRewardsDistributor {
    error AlreadySet();
    error InsufficientAdminFee();
    error InsufficientReward();
    error InvalidAdminFee();
    error InvalidHintsLength();
    error InvalidRewardTimestamp();
    error NoDeposits();
    error NoRewardsToClaim();
    error NotNetwork();
    error NotNetworkMiddleware();
    error NotVault();
    error NotVaultOwner();
    error NotWhitelistedNetwork();

    /**
     * @notice Structure for a reward distribution.
     * @param network network on behalf of which the reward is distributed
     * @param amount amount of tokens to be distributed (admin fee is excluded)
     * @param timestamp time point stakes must taken into account at
     * @param creation time point the reward distribution was created at
     */
    struct RewardDistribution {
        address network;
        uint256 amount;
        uint48 timestamp;
        uint48 creation;
    }

    /**
     * @notice Emitted when a reward is claimed.
     * @param token address of the token claimed
     * @param rewardIndex index of the reward distribution
     * @param claimer account that claimed the reward
     * @param recipient account that received the reward
     * @param claimedAmount amount of tokens claimed
     */
    event ClaimReward(
        address indexed token,
        uint256 indexed rewardIndex,
        address indexed claimer,
        address recipient,
        uint256 claimedAmount
    );

    /**
     * @notice Emitted when an admin fee is claimed.
     * @param recipient account that received the fee
     * @param amount amount of the fee claimed
     */
    event ClaimAdminFee(address indexed recipient, uint256 amount);

    /**
     * @notice Emitted when a network whitelist status is set.
     * @param network network for which the whitelist status is set
     * @param status if whitelisted the network
     */
    event SetNetworkWhitelistStatus(address indexed network, bool status);

    /**
     * @notice Emitted when an admin fee is set.
     * @param adminFee admin fee
     */
    event SetAdminFee(uint256 adminFee);

    /**
     * @notice Get the maximum admin fee (= 100%).
     * @return maximum admin fee
     */
    function ADMIN_FEE_BASE() external view returns (uint256);

    /**
     * @notice Get the admin fee claimer's role.
     */
    function ADMIN_FEE_CLAIM_ROLE() external view returns (bytes32);

    /**
     * @notice Get the network whitelist status setter's role.
     */
    function NETWORK_WHITELIST_ROLE() external view returns (bytes32);

    /**
     * @notice Get the admin fee setter's role.
     */
    function ADMIN_FEE_SET_ROLE() external view returns (bytes32);

    /**
     * @notice Get the network registry's address.
     * @return address of the network registry
     */
    function NETWORK_REGISTRY() external view returns (address);

    /**
     * @notice Get the vault factory's address.
     * @return address of the vault factory
     */
    function VAULT_FACTORY() external view returns (address);

    /**
     * @notice Get the network middleware service's address.
     * @return address of the network middleware service
     */
    function NETWORK_MIDDLEWARE_SERVICE() external view returns (address);

    /**
     * @notice Get the vault's address.
     * @return address of the vault
     */
    function VAULT() external view returns (address);

    /**
     * @notice Get an admin fee.
     * @return admin fee
     */
    function adminFee() external view returns (uint256);

    /**
     * @notice Get if a given account is a whitelisted network.
     * @param account address to check
     */
    function isNetworkWhitelisted(address account) external view returns (bool);

    /**
     * @notice Get a total number of rewards using a particular token.
     * @param token address of the token
     * @return total number of the rewards using the token
     */
    function rewardsLength(address token) external view returns (uint256);

    /**
     * @notice Get a particular reward distribution.
     * @param token address of the token
     * @param rewardIndex index of the reward distribution using the token
     * @return network network on behalf of which the reward is distributed
     * @return amount amount of tokens to be distributed
     * @return timestamp time point stakes must taken into account at
     * @return creation time point the reward distribution was created at
     */
    function rewards(
        address token,
        uint256 rewardIndex
    ) external view returns (address network, uint256 amount, uint48 timestamp, uint48 creation);

    /**
     * @notice Get a first index of the unclaimed rewards using a particular token by a given account.
     * @param account address of the account
     * @param token address of the token
     * @return first index of the unclaimed rewards
     */
    function lastUnclaimedReward(address account, address token) external view returns (uint256);

    /**
     * @notice Get a claimable admin fee amount for a particular token.
     * @param token address of the token
     * @return claimable admin fee
     */
    function claimableAdminFee(address token) external view returns (uint256);

    /**
     * @notice Claim rewards for a particular token.
     * @param recipient account that will receive the rewards
     * @param token address of the token
     * @param maxRewards maximum amount of rewards to process
     * @param activeSharesOfHints hint indexes to optimize `activeSharesOf()` processing
     */
    function claimRewards(
        address recipient,
        address token,
        uint256 maxRewards,
        uint32[] calldata activeSharesOfHints
    ) external;

    /**
     * @notice Claim an admin fee.
     * @param recipient account that will receive the fee
     * @param token address of the token
     * @dev Only the vault owner can call this function.
     */
    function claimAdminFee(address recipient, address token) external;

    /**
     * @notice Set a network whitelist status (it allows networks to distribute rewards).
     * @param network address of the network
     * @param status if whitelisting the network
     * @dev Only the NETWORK_WHITELIST_ROLE holder can call this function.
     */
    function setNetworkWhitelistStatus(address network, bool status) external;

    /**
     * @notice Set an admin fee.
     * @param adminFee admin fee (up to ADMIN_FEE_BASE inclusively)
     * @dev Only the ADMIN_FEE_SET_ROLE holder can call this function.
     */
    function setAdminFee(uint256 adminFee) external;
}
