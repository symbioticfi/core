// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IPlugin} from "src/interfaces/base/IPlugin.sol";

interface IRewardsPlugin is IPlugin {
    error InsufficientAdminFee();
    error InsufficientReward();
    error InvalidHintsLength();
    error InvalidRewardTimestamp();
    error NoDeposits();
    error NoRewardsToClaim();
    error NotNetwork();
    error NotOwner();
    error NotVault();
    error UnacceptedAdminFee();

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
     * @notice Emitted when a reward is distributed.
     * @param vault address of the vault
     * @param token address of the token to be distributed
     * @param rewardIndex index of the reward distribution
     * @param network network on behalf of which the reward is distributed
     * @param amount amount of tokens distributed (admin fee is included)
     * @param timestamp time point stakes must taken into account at
     */
    event DistributeReward(
        address indexed vault,
        address indexed token,
        uint256 rewardIndex,
        address indexed network,
        uint256 amount,
        uint48 timestamp
    );

    /**
     * @notice Emitted when a reward is claimed.
     * @param vault address of the vault
     * @param token address of the token claimed
     * @param rewardIndex index of the reward distribution
     * @param claimer account that claimed the reward
     * @param recipient account that received the reward
     * @param claimedAmount amount of tokens claimed
     */
    event ClaimReward(
        address indexed vault,
        address indexed token,
        uint256 rewardIndex,
        address indexed claimer,
        address recipient,
        uint256 claimedAmount
    );

    /**
     * @notice Emitted when an admin fee is claimed.
     * @param vault address of the vault
     * @param recipient account that received the fee
     * @param amount amount of the fee claimed
     */
    event ClaimAdminFee(address indexed vault, address indexed recipient, uint256 amount);

    /**
     * @notice Get the address of the vault registry.
     * @return address of the vault registry
     */
    function VAULT_REGISTRY() external view returns (address);

    /**
     * @notice Get a total number of rewards using a particular token.
     * @param vault address of the vault
     * @param token address of the token
     * @return total number of rewards using the token
     */
    function rewardsLength(address vault, address token) external view returns (uint256);

    /**
     * @notice Get a reward distribution.
     * @param vault address of the vault
     * @param token address of the token
     * @param rewardIndex index of the reward distribution
     * @return network network on behalf of which the reward is distributed
     * @return amount amount of tokens to be distributed
     * @return timestamp time point stakes must taken into account at
     * @return creation timestamp when the reward distribution was created
     */
    function rewards(
        address vault,
        address token,
        uint256 rewardIndex
    ) external view returns (address network, uint256 amount, uint48 timestamp, uint48 creation);

    /**
     * @notice Get a first index of the unclaimed rewards using a particular token by a given account.
     * @param vault address of the vault
     * @param account address of the account
     * @param token address of the token
     * @return first index of the unclaimed rewards
     */
    function lastUnclaimedReward(address vault, address account, address token) external view returns (uint256);

    /**
     * @notice Get a claimable fee amount for a particular token.
     * @param vault address of the vault
     * @param token address of the token
     * @return claimable fee
     */
    function claimableAdminFee(address vault, address token) external view returns (uint256);

    /**
     * @notice Distribute rewards on behalf of a particular network using a given token.
     * @param vault address of the vault
     * @param network address of the network
     * @param token address of the token
     * @param amount amount of tokens to distribute
     * @param timestamp time point stakes must taken into account at
     * @param acceptedAdminFee maximum accepted admin fee
     * @return rewardIndex index of the reward distribution
     */
    function distributeReward(
        address vault,
        address network,
        address token,
        uint256 amount,
        uint48 timestamp,
        uint256 acceptedAdminFee
    ) external returns (uint256 rewardIndex);

    /**
     * @notice Claim rewards for a particular token.
     * @param vault address of the vault
     * @param recipient account that will receive the rewards
     * @param token address of the token
     * @param maxRewards max amount of rewards to process
     * @param activeSharesOfHints hint indexes to optimize `activeSharesOf()` processing
     */
    function claimRewards(
        address vault,
        address recipient,
        address token,
        uint256 maxRewards,
        uint32[] calldata activeSharesOfHints
    ) external;

    /**
     * @notice Claim admin fee.
     * @param vault address of the vault
     * @param recipient account that receives the fee
     * @param token address of the token
     * @dev Only the owner can call this function.
     */
    function claimAdminFee(address vault, address recipient, address token) external;
}
