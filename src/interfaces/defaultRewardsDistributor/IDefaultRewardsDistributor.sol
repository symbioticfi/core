// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IRewardsDistributor} from "src/interfaces/base/IRewardsDistributor.sol";

interface IDefaultRewardsDistributor is IRewardsDistributor {
    error AlreadySet();
    error InsufficientAdminFee();
    error InsufficientReward();
    error InvalidHintsLength();
    error InvalidRewardTimestamp();
    error NoDeposits();
    error NoRewardsToClaim();
    error NotNetworkMiddleware();
    error NotVault();
    error NotVaultOwner();
    error NotWhitelistedNetwork();

    /**
     * @notice Structure for a reward distribution.
     * @param network network on behalf of which the reward is distributed
     * @param amount amount of tokens to be distributed (admin fee is excluded)
     * @param timestamp time point stakes must taken into account at
     * @param creation timestamp when the reward distribution was created
     */
    struct RewardDistribution {
        address network;
        uint256 amount;
        uint48 timestamp;
        uint48 creation;
    }

    /**
     * @notice Emitted when a network whitelist status is set.
     * @param network network for which the whitelist status is set
     * @param status whitelist status
     */
    event SetNetworkWhitelistStatus(address indexed network, bool status);

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
     * @notice Get if a given account is a whitelisted network.
     * @param account address to check
     */
    function isNetworkWhitelisted(address account) external view returns (bool);

    /**
     * @notice Get a total number of rewards using a particular token.
     * @param token address of the token
     * @return total number of rewards using the token
     */
    function rewardsLength(address token) external view returns (uint256);

    /**
     * @notice Get a reward distribution.
     * @param token address of the token
     * @param rewardIndex index of the reward distribution
     * @return network network on behalf of which the reward is distributed
     * @return amount amount of tokens to be distributed
     * @return timestamp time point stakes must taken into account at
     * @return creation timestamp when the reward distribution was created
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
     * @notice Get a claimable fee amount for a particular token.
     * @param token address of the token
     * @return claimable fee
     */
    function claimableAdminFee(address token) external view returns (uint256);

    /**
     * @notice Set a network whitelist status (it allows networks to distribute rewards).
     * @param network address of the network
     * @dev Only the vault owner can call this function.
     */
    function setNetworkWhitelistStatus(address network, bool status) external;

    /**
     * @notice Claim rewards for a particular token.
     * @param recipient account that will receive the rewards
     * @param token address of the token
     * @param maxRewards max amount of rewards to process
     * @param activeSharesOfHints hint indexes to optimize `activeSharesOf()` processing
     */
    function claimRewards(
        address recipient,
        address token,
        uint256 maxRewards,
        uint32[] calldata activeSharesOfHints
    ) external;

    /**
     * @notice Claim admin fee.
     * @param recipient account that receives the fee
     * @param token address of the token
     * @dev Only the vault owner can call this function.
     */
    function claimAdminFee(address recipient, address token) external;
}
