// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

/**
 * @title IWithdrawalQueue
 * @notice Interface for the WithdrawalQueue contract.
 */
interface IWithdrawalQueue is IERC721Metadata {
    /* STRUCTS */

    /**
     * @notice A pending withdrawal request.
     * @param shares Amount of vault shares requested for withdrawal.
     * @param claimedShares Amount of request shares already claimed.
     * @param prevRequestSum Cumulative requested shares before this request.
     */
    struct WithdrawalRequest {
        uint256 shares;
        uint256 claimedShares;
        uint256 prevRequestSum;
    }

    /**
     * @notice Share price checkpoint used for partial withdrawal claims.
     * @param totalAssets Total assets used for the checkpoint share price.
     * @param totalShares Total shares used for the checkpoint share price.
     */
    struct SharePriceCheckpoint {
        uint256 totalAssets;
        uint256 totalShares;
    }

    /**
     * @notice Reward checkpoint claimed by the queue for withdrawal requests.
     * @param timestamp Timestamp of the source vault reward snapshot.
     * @param amount Amount of reward tokens claimed by the queue.
     * @param totalShares Total active withdrawal shares linked to the reward.
     */
    struct RewardCheckpoint {
        uint48 timestamp;
        uint256 amount;
        uint256 totalShares;
    }

    /* ERRORS */

    /**
     * @notice Reverts when a request is made by a non-vault account.
     */
    error NotVault();

    // /**
    //  * @notice Reverts when there are no rewards to claim.
    //  */
    // error NoRewardsToClaim();

    /**
     * @notice Reverts when a request is made with zero shares.
     */
    error ZeroShares();

    /* EVENTS */

    /**
     * @notice Emitted when a withdrawal request is created.
     * @param requester Account that requested the withdrawal.
     * @param receiver Account that received the withdrawal NFT.
     * @param shares Amount of vault shares requested for withdrawal.
     * @param tokenId Withdrawal NFT id.
     */
    event RequestWithdraw(address indexed requester, address indexed receiver, uint256 shares, uint256 indexed tokenId);

    /**
     * @notice Emitted when a withdrawal request is claimed.
     * @param tokenId Withdrawal NFT id.
     * @param assetsClaimed Amount of assets claimed.
     * @param sharesClaimed Amount of request shares claimed.
     */
    event Claim(uint256 indexed tokenId, uint256 assetsClaimed, uint256 sharesClaimed);

    /**
     * @notice Emitted when pending withdrawal requests are filled.
     * @param assets Amount of assets used to fill the queue.
     * @param shares Amount of vault shares filled.
     */
    event Fill(uint256 assets, uint256 shares);

    // /**
    //  * @notice Emitted when the queue claims vault snapshot rewards.
    //  * @param vaultSnapshotRewards Vault snapshot rewards contract.
    //  * @param network Network whose rewards were claimed.
    //  * @param token Reward token claimed.
    //  * @param amount Amount of reward tokens claimed by the queue.
    //  * @param firstClaimedReward First source reward index claimed.
    //  * @param rewardsClaimed Number of source reward distributions claimed.
    //  */
    // event ClaimVaultSnapshotRewards(
    //     address indexed vaultSnapshotRewards,
    //     address indexed network,
    //     address indexed token,
    //     uint256 amount,
    //     uint256 firstClaimedReward,
    //     uint256 rewardsClaimed
    // );

    // /**
    //  * @notice Emitted when withdrawal rewards are claimed.
    //  * @param tokenId Withdrawal NFT id.
    //  * @param vaultSnapshotRewards Vault snapshot rewards contract.
    //  * @param network Network whose rewards were claimed.
    //  * @param token Reward token claimed.
    //  * @param amount Amount of reward tokens sent to the withdrawal receiver.
    //  * @param firstClaimedReward First queue reward index claimed.
    //  * @param rewardsClaimed Number of queue reward distributions claimed.
    //  */
    // event ClaimRewards(
    //     uint256 indexed tokenId,
    //     address indexed vaultSnapshotRewards,
    //     address indexed network,
    //     address token,
    //     uint256 amount,
    //     uint256 firstClaimedReward,
    //     uint256 rewardsClaimed
    // );

    /* FUNCTIONS */

    /**
     * @notice Returns the ERC4626 vault accepted by the queue.
     * @return vaultToken ERC4626 vault address.
     */
    function vault() external view returns (address vaultToken);

    /**
     * @notice Executes multiple calls against the queue.
     * @param data Encoded calls to execute.
     */
    function multicall(bytes[] calldata data) external;

    /**
     * @notice Total vault shares requested for withdrawal.
     * @return requested Total requested shares.
     */
    function totalRequested() external view returns (uint256 requested);

    /**
     * @notice Total vault shares filled.
     * @return filled Total filled shares.
     */
    function totalFilled() external view returns (uint256 filled);

    /**
     * @notice Returns the pending assets in the queue.
     * @return assets Pending assets.
     */
    function pendingAssets() external view returns (uint256 assets);

    /**
     * @notice Returns the pending shares in the queue.
     * @return shares Pending shares.
     */
    function pendingShares() external view returns (uint256 shares);

    /**
     * @notice Returns the request details for a withdrawal NFT.
     * @param tokenId Withdrawal NFT id.
     * @return shares Amount of vault shares requested for withdrawal.
     * @return claimedShares Amount of request shares already claimed.
     * @return prevRequestSum Cumulative requested shares before this request.
     */
    function requests(uint256 tokenId)
        external
        view
        returns (uint256 shares, uint256 claimedShares, uint256 prevRequestSum);

    /**
     * @notice Transfers vault shares into the queue and mints a withdrawal NFT.
     * @param shares Amount of vault shares to request for withdrawal.
     * @param receiver Address that receives the withdrawal NFT.
     * @return tokenId Minted withdrawal NFT id.
     */
    function requestWithdraw(uint256 shares, address receiver) external returns (uint256 tokenId);

    /**
     * @notice Claims a withdrawal request.
     * @param tokenId Withdrawal NFT id.
     * @param maxIterations Maximum number of share price checkpoints to process.
     * @return assetsClaimed Amount of assets claimed.
     * @return sharesClaimed Amount of request shares claimed.
     */
    function claim(uint256 tokenId, uint256 maxIterations)
        external
        returns (uint256 assetsClaimed, uint256 sharesClaimed);

    // /**
    //  * @notice Claims vault snapshot rewards for the queue.
    //  * @param vaultSnapshotRewards Vault snapshot rewards contract.
    //  * @param network Network whose rewards should be claimed.
    //  * @param token Reward token to claim.
    //  * @param rewardsToClaim Maximum number of source rewards to process.
    //  * @param activeSharesOfHints Hints for the queue active shares lookups in the rewards contract.
    //  * @return amount Amount of reward tokens claimed by the queue.
    //  * @return rewardsClaimed Number of source reward distributions claimed.
    //  */
    // function claimVaultSnapshotRewards(
    //     address vaultSnapshotRewards,
    //     address network,
    //     address token,
    //     uint256 rewardsToClaim,
    //     bytes[] calldata activeSharesOfHints
    // ) external returns (uint256 amount, uint256 rewardsClaimed);

    // /**
    //  * @notice Claims queued rewards for a withdrawal NFT.
    //  * @param tokenId Withdrawal NFT id.
    //  * @param vaultSnapshotRewards Vault snapshot rewards contract.
    //  * @param network Network whose rewards should be claimed.
    //  * @param token Reward token to claim.
    //  * @param rewardsToClaim Maximum number of queue rewards to process.
    //  * @return amount Amount of reward tokens sent to the withdrawal receiver.
    //  * @return rewardsClaimed Number of queue reward distributions claimed.
    //  */
    // function claimRewards(
    //     uint256 tokenId,
    //     address vaultSnapshotRewards,
    //     address network,
    //     address token,
    //     uint256 rewardsToClaim
    // ) external returns (uint256 amount, uint256 rewardsClaimed);

    /**
     * @notice Returns the claimable assets and shares for a withdrawal request.
     * @param tokenId Withdrawal NFT id.
     * @return assetsClaimed Claimable assets.
     * @return sharesClaimed Claimable shares.
     */
    function claimable(uint256 tokenId) external view returns (uint256 assetsClaimed, uint256 sharesClaimed);

    /**
     * @notice Fills pending withdrawal requests with available vault assets.
     */
    function fill() external;
}
