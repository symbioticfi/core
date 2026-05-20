// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

// import {IVaultSnapshotRewards} from "../../interfaces/vault/IVaultSnapshotRewards.sol";
import {IDelegator} from "../../interfaces/delegator/IDelegator.sol";
import {IWithdrawalQueue} from "../../interfaces/vault/IWithdrawalQueue.sol";
import {DECIMALS_OFFSET, IVaultV2} from "../../interfaces/vault/IVaultV2.sol";

/// @title Withdrawal Queue
/// @notice Holds pending share withdrawal requests as ERC721 positions.
contract WithdrawalQueue is ERC721Upgradeable, IWithdrawalQueue {
    using SafeERC20 for IERC4626;
    using SafeERC20 for IERC20;
    using Math for uint256;
    using Checkpoints for Checkpoints.Trace256;

    /* IMMUTABLES */

    /* STATE VARIABLES */

    /// @inheritdoc IWithdrawalQueue
    address public vault;
    /// @inheritdoc IWithdrawalQueue
    uint256 public totalFilled;
    /// @inheritdoc IWithdrawalQueue
    uint256 public totalRequested;

    /// @dev The next withdrawal NFT id.
    uint256 internal _nextTokenId;
    /// @dev The latest total assets.
    uint256 internal _latestTotalAssets;
    /// @dev The latest total shares.
    uint256 internal _latestTotalShares;
    /// @dev Share price checkpoints.
    SharePriceCheckpoint[] internal _sharePriceCheckpoints;
    /// @dev Cumulative shares filled to share price.
    Checkpoints.Trace256 internal _totalFilledSharesToSharePrice;
    /// @dev Total requested shares checkpoints by timestamp.
    Checkpoints.Trace256 internal _totalRequestedAt;
    /// @dev Total filled shares checkpoints by timestamp.
    Checkpoints.Trace256 internal _totalFilledAt;
    /// @inheritdoc IWithdrawalQueue
    mapping(uint256 tokenId => WithdrawalRequest) public requests;
    /// @dev Queue rewards claimed from vault snapshot rewards contracts.
    mapping(
        address vaultSnapshotRewards => mapping(address network => mapping(address token => RewardCheckpoint[]))
    ) internal _rewards;
    /// @inheritdoc IWithdrawalQueue
    mapping(
        uint256 tokenId
            => mapping(address vaultSnapshotRewards => mapping(address network => mapping(address token => uint256)))
    ) public lastClaimedReward;

    /* MULTICALL */

    /// @inheritdoc IWithdrawalQueue
    function multicall(bytes[] calldata data) public {
        for (uint256 i; i < data.length; ++i) {
            (bool success, bytes memory returnData) = address(this).delegatecall(data[i]);
            if (!success) {
                assembly ("memory-safe") {
                    revert(add(32, returnData), mload(returnData))
                }
            }
        }
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc IWithdrawalQueue
    function pendingAssets() public view returns (uint256) {
        return IERC4626(vault).previewRedeem(pendingShares());
    }

    /// @inheritdoc IWithdrawalQueue
    function pendingShares() public view returns (uint256) {
        return totalRequested - totalFilled;
    }

    /// @inheritdoc IWithdrawalQueue
    function claimable(uint256 tokenId) public view returns (uint256 assetsClaimed, uint256 sharesClaimed) {
        (assetsClaimed, sharesClaimed) = _claimable(tokenId, type(uint256).max);
    }

    /// @inheritdoc IWithdrawalQueue
    function rewards(address vaultSnapshotRewards, address network, address token, uint256 index)
        public
        view
        returns (RewardCheckpoint memory checkpoint)
    {
        return _rewards[vaultSnapshotRewards][network][token][index];
    }

    /// @inheritdoc IWithdrawalQueue
    function rewardsLength(address vaultSnapshotRewards, address network, address token)
        public
        view
        returns (uint256 length)
    {
        return _rewards[vaultSnapshotRewards][network][token].length;
    }

    /* PUBLIC FUNCTIONS */

    /// @inheritdoc IWithdrawalQueue
    function requestWithdraw(uint256 shares, address receiver) public returns (uint256 tokenId) {
        if (shares == 0) {
            revert ZeroShares();
        }

        IERC4626(vault).safeTransferFrom(msg.sender, address(this), shares);

        tokenId = _nextTokenId++;
        requests[tokenId] =
            WithdrawalRequest({receiver: receiver, shares: shares, claimedShares: 0, prevRequestSum: totalRequested});
        totalRequested += shares;
        _totalRequestedAt.push(block.timestamp, totalRequested);

        _mint(receiver, tokenId);

        IDelegator(IVaultV2(vault).delegator())
            .onRequestWithdraw(msg.sender, receiver, IERC4626(vault).previewRedeem(shares), shares);

        emit RequestWithdraw(msg.sender, receiver, shares, tokenId);
    }

    /// @inheritdoc IWithdrawalQueue
    function claim(uint256 tokenId, uint256 maxIterations)
        public
        returns (uint256 assetsClaimed, uint256 sharesClaimed)
    {
        (assetsClaimed, sharesClaimed) = _claimable(tokenId, maxIterations);

        WithdrawalRequest storage request = requests[tokenId];

        request.claimedShares += sharesClaimed;

        IERC20(IERC4626(vault).asset()).safeTransfer(request.receiver, assetsClaimed);

        emit Claim(tokenId, assetsClaimed, sharesClaimed);
    }

    /*
    /// @inheritdoc IWithdrawalQueue
    function claimVaultSnapshotRewards(
        address vaultSnapshotRewards,
        address network,
        address token,
        uint256 rewardsToClaim,
        bytes[] calldata activeSharesOfHints
    ) public returns (uint256 amount, uint256 rewardsClaimed) {
        uint256 firstRewardToClaim =
            IVaultSnapshotRewards(vaultSnapshotRewards).lastUnclaimedReward(address(this), vault, network, token);
        rewardsClaimed = Math.min(
            rewardsToClaim,
            IVaultSnapshotRewards(vaultSnapshotRewards).rewardsLength(vault, network, token).saturatingSub(
                firstRewardToClaim
            )
        );
        if (rewardsClaimed == 0) {
            revert NoRewardsToClaim();
        }

        for (uint256 i; i < rewardsClaimed; ++i) {
            bytes memory activeSharesOfHint;
            if (i < activeSharesOfHints.length) {
                activeSharesOfHint = activeSharesOfHints[i];
            }
            amount += _claimVaultSnapshotReward(
                vaultSnapshotRewards, network, token, firstRewardToClaim + i, activeSharesOfHint
            );
        }

        emit ClaimVaultSnapshotRewards(vaultSnapshotRewards, network, token, amount, firstRewardToClaim, rewardsClaimed);
    }

    /// @inheritdoc IWithdrawalQueue
    function claimRewards(
        uint256 tokenId,
        address vaultSnapshotRewards,
        address network,
        address token,
        uint256 rewardsToClaim
    ) public returns (uint256 amount, uint256 rewardsClaimed) {
        ownerOf(tokenId);

        uint256 firstRewardToClaim = lastClaimedReward[tokenId][vaultSnapshotRewards][network][token];
        RewardCheckpoint[] storage rewards_ = _rewards[vaultSnapshotRewards][network][token];
        rewardsClaimed = Math.min(rewardsToClaim, rewards_.length.saturatingSub(firstRewardToClaim));
        if (rewardsClaimed == 0) {
            revert NoRewardsToClaim();
        }
        WithdrawalRequest storage request = requests[tokenId];

        for (uint256 i; i < rewardsClaimed; ++i) {
            RewardCheckpoint storage reward = rewards_[firstRewardToClaim + i];
            if (reward.totalShares == 0 || reward.amount == 0) {
                continue;
            }
            amount += _activeSharesOfAt(request, reward.timestamp).mulDiv(reward.amount, reward.totalShares);
        }

        lastClaimedReward[tokenId][vaultSnapshotRewards][network][token] = firstRewardToClaim + rewardsClaimed;

        if (amount != 0) {
            IERC20(token).safeTransfer(request.receiver, amount);
        }

        emit ClaimRewards(tokenId, vaultSnapshotRewards, network, token, amount, firstRewardToClaim, rewardsClaimed);
    }
    */

    /* PUBLIC FUNCTIONS (PERMISSIONLESS) */

    /// @inheritdoc IWithdrawalQueue
    function fill(uint256 amount) public {
        amount = Math.min(amount, pendingAssets());
        if (amount == 0) {
            return;
        }

        address delegator = IVaultV2(vault).delegator();
        IDelegator(delegator).sync();
        amount = Math.min(amount, IERC20(IERC4626(vault).asset()).balanceOf(vault));

        uint256 shares = IERC4626(vault).previewWithdraw(amount);
        if (shares == 0) {
            return;
        }

        uint256 totalShares = IERC4626(vault).totalSupply();
        uint256 totalAssets = IERC4626(vault).totalAssets();
        IERC4626(vault).redeem(shares, address(this), address(this));

        // if share price has changed, update the checkpoint
        if (_latestTotalAssets * totalShares != _latestTotalShares * totalAssets) {
            _totalFilledSharesToSharePrice.push(totalFilled, _sharePriceCheckpoints.length);
            _sharePriceCheckpoints.push(
                SharePriceCheckpoint({totalAssets: _latestTotalAssets, totalShares: _latestTotalShares})
            );

            _latestTotalAssets = totalAssets;
            _latestTotalShares = totalShares;
        }
        totalFilled += shares;
        _totalFilledAt.push(block.timestamp, totalFilled);

        emit Fill(amount, shares);
    }

    /// @dev Returns the claimable assets and shares for a withdrawal request.
    /// @param tokenId The withdrawal NFT id.
    /// @param maxIterations The maximum number of iterations to claim.
    /// @return assetsClaimed The claimable assets.
    /// @return sharesClaimed The claimable shares.
    function _claimable(uint256 tokenId, uint256 maxIterations)
        internal
        view
        returns (uint256 assetsClaimed, uint256 sharesClaimed)
    {
        WithdrawalRequest storage request = requests[tokenId];

        if (request.claimedShares == request.shares) {
            return (0, 0);
        }

        uint256 maxSharesToClaim =
            totalFilled.saturatingSub(request.prevRequestSum + request.shares - request.claimedShares);
        uint256 cumClaimedShares = request.prevRequestSum + request.claimedShares;
        uint32 checkpointIndex =
            uint32(_totalFilledSharesToSharePrice.upperLookupRecent(cumClaimedShares.saturatingSub(1)));

        for (; maxSharesToClaim > 0 && maxIterations > 0; --maxIterations) {
            SharePriceCheckpoint storage checkpoint = _sharePriceCheckpoints[checkpointIndex++];
            uint256 curRequestShares = maxSharesToClaim;
            if (_totalFilledSharesToSharePrice.length() > checkpointIndex) {
                curRequestShares = Math.min(
                    _totalFilledSharesToSharePrice.at(checkpointIndex)._key - cumClaimedShares, maxSharesToClaim
                );
            }
            assetsClaimed += curRequestShares.mulDiv(
                checkpoint.totalAssets + 1,
                checkpoint.totalShares + 10 ** DECIMALS_OFFSET // TODO: Not good
            );
            cumClaimedShares += curRequestShares;
            maxSharesToClaim -= curRequestShares;
        }

        sharesClaimed = cumClaimedShares - request.prevRequestSum - request.claimedShares;
    }

    /// @dev Returns total active withdrawal shares at a timestamp.
    /// @param timestamp Timestamp to query.
    /// @return shares Total active withdrawal shares.
    function _activeSharesAt(uint48 timestamp) internal view returns (uint256 shares) {
        return _totalRequestedAt.upperLookupRecent(timestamp).saturatingSub(_totalFilledAt.upperLookupRecent(timestamp));
    }

    /// @dev Returns active withdrawal shares for a request at a timestamp.
    /// @param request Withdrawal request to query.
    /// @param timestamp Timestamp to query.
    /// @return shares Request active withdrawal shares.
    function _activeSharesOfAt(WithdrawalRequest storage request, uint48 timestamp)
        internal
        view
        returns (uint256 shares)
    {
        uint256 requestStart = request.prevRequestSum;
        uint256 requestEnd = requestStart + request.shares;
        uint256 activeStart = Math.max(requestStart, _totalFilledAt.upperLookupRecent(timestamp));
        uint256 activeEnd = Math.min(requestEnd, _totalRequestedAt.upperLookupRecent(timestamp));

        return activeEnd.saturatingSub(activeStart);
    }

    /*
    /// @dev Claims and records a single vault snapshot reward for the queue.
    /// @param vaultSnapshotRewards Vault snapshot rewards contract address.
    /// @param network Network whose rewards are claimed.
    /// @param token Reward token to claim.
    /// @param rewardIndex Source reward index to claim.
    /// @param activeSharesOfHint Hint for the queue active shares lookup in the rewards contract.
    /// @return rewardAmount Amount of reward tokens claimed by the queue.
    function _claimVaultSnapshotReward(
        address vaultSnapshotRewards,
        address network,
        address token,
        uint256 rewardIndex,
        bytes memory activeSharesOfHint
    ) internal returns (uint256 rewardAmount) {
        IVaultSnapshotRewards.RewardDistribution memory reward =
            IVaultSnapshotRewards(vaultSnapshotRewards).rewards(vault, network, token, rewardIndex);
        uint256 balanceBefore = IERC20(token).balanceOf(address(this));
        bytes[] memory activeSharesOfHints = new bytes[](1);
        activeSharesOfHints[0] = activeSharesOfHint;

        IVaultSnapshotRewards(vaultSnapshotRewards).claimVaultSnapshotRewards(
            address(this), network, token, vault, rewardIndex, rewardIndex, 1, activeSharesOfHints
        );

        rewardAmount = IERC20(token).balanceOf(address(this)) - balanceBefore;
        uint256 totalShares = _activeSharesAt(reward.timestamp);

        _rewards[vaultSnapshotRewards][network][token].push(
            RewardCheckpoint({timestamp: reward.timestamp, amount: rewardAmount, totalShares: totalShares})
        );
    }
    */

    /* INITIALIZE */

    /// @dev Initialize withdrawal queue metadata and bind it to the calling vault.
    function initialize() public initializer {
        __ERC721_init("Withdrawal Queue", "WQ");

        vault = msg.sender;

        _latestTotalAssets = 1;
        _latestTotalShares = 10 ** DECIMALS_OFFSET;
    }
}
