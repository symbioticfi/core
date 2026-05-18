// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {IWithdrawalQueue} from

/// @title Withdrawal Queue
/// @author Symbiotic Re contributors
/// @notice Holds pending SymRe share withdrawal requests as ERC721 positions.
contract WithdrawalQueue is ERC721, IWithdrawalQueue {
    using SafeERC20 for IERC4626;
    using SafeERC20 for IERC20;
    using Math for uint256;
    using Checkpoints for Checkpoints.Trace256;

    /// @notice A pending withdrawal request.
    /// @param shares The amount of SymRe shares pending withdrawal.
    /// @param receiver The address that received the withdrawal NFT.
    /// @param owner The address that supplied the SymRe shares.
    struct WithdrawalRequest {
        uint256 shares;
        address receiver;
        address owner;
        uint256 claimedShares;
        uint256 prevRequestSum;
    }

    struct SharePriceCheckpoint {
        uint256 filledShares;
        uint256 totalAssets;
        uint256 totalShares;
    }

    /// @notice Share price checkpoints.
    SharePriceCheckpoint[] private _sharePriceCheckpoints;

    /// @notice Emitted when a withdrawal request is created.
    /// @param tokenId The withdrawal NFT id.
    /// @param shares The amount of SymRe shares pending withdrawal.
    /// @param receiver The address that received the withdrawal NFT.
    /// @param owner The address that supplied the SymRe shares.
    event WithdrawalRequested(uint256 indexed tokenId, uint256 shares, address indexed receiver, address indexed owner);

    /// @notice Emitted when a withdrawal request is claimed.
    /// @param tokenId The withdrawal NFT id.
    /// @param assetsToClaim The amount of assets claimed.
    event WithdrawalClaimed(uint256 indexed tokenId, uint256 assetsToClaim);

    /// @notice Reverts when a request is made with zero shares.
    error ZeroShares();
    /// @notice Reverts when a request is made with too many shares.
    error TooManySharesToFill();
    /// @notice Reverts when a withdrawal request is already claimed.
    error WithdrawalAlreadyClaimed();

    /// @notice The SymRe share token accepted by the queue.
    IERC4626 private immutable SYM_RE;

    /// @notice Total SymRe shares requested for withdrawal.
    uint256 public totalRequested;
    /// @notice Total SymRe shares filled.
    uint256 public totalFilled;
    /// @notice The next withdrawal NFT id.
    uint256 private _nextTokenId = 1;

    /// @notice Withdrawal requests.
    mapping(uint256 tokenId => WithdrawalRequest request) private _requests;

    /// @notice Cumulative shares filled to share price.
    Checkpoints.Trace256 private _cumFilledSharesToSharePrice;

    /// @notice The latest total assets.
    uint256 private _latestTotalAssets;

    /// @notice The latest total shares.
    uint256 private _latestTotalShares;

    /// @notice Initializes the withdrawal queue.
    /// @param symRe_ The SymRe share token accepted by the queue.
    constructor(address symRe_) ERC721("SymRe Withdrawal Queue", "symReWQ") {
        SYM_RE = IERC4626(symRe_);

        // init with 1 to have initial share price at 1
        _latestTotalAssets = 1;
        _latestTotalShares = 1;
    }

    /// @notice Returns the SymRe share token accepted by the queue.
    /// @return The SymRe share token.
    function symRe() external view returns (IERC4626) {
        return SYM_RE;
    }

    /// @notice Returns the pending assets in the queue.
    /// @return The pending assets in the queue.
    function pendingAssets() public view returns (uint256) {
        return SYM_RE.convertToAssets(pendingShares());
    }

    /// @notice Returns the pending shares in the queue.
    /// @return The pending shares in the queue.
    function pendingShares() public view returns (uint256) {
        return totalRequested - totalFilled;
    }

    /// @notice Returns the pending request details for a withdrawal NFT.
    /// @param tokenId The withdrawal NFT id.
    /// @return withdrawalRequest The pending withdrawal request.
    function getRequest(uint256 tokenId) external view returns (WithdrawalRequest memory withdrawalRequest) {
        withdrawalRequest = _requests[tokenId];
    }

    // function reportNavUpdate() external {
    //     if (msg.sender != address(SYM_RE)) {
    //         revert NotAuthorized();
    //     }
    //     _navUpdated = true;
    // }

    /// @notice Transfers SymRe shares into the queue and mints a withdrawal NFT.
    /// @param shares The amount of SymRe shares to request for withdrawal.
    /// @param receiver The address that receives the withdrawal NFT.
    /// @param owner The address supplying the SymRe shares.
    /// @return tokenId The minted withdrawal NFT id.
    function requestWithdrawal(uint256 shares, address receiver, address owner) external returns (uint256 tokenId) {
        if (shares == 0) {
            revert ZeroShares();
        }

        tokenId = _nextTokenId++;
        _requests[tokenId] = WithdrawalRequest({
            shares: shares,
            receiver: receiver,
            owner: owner,
            claimedShares: 0,
            prevRequestSum: totalRequested
        });
        totalRequested += shares;

        SYM_RE.safeTransferFrom(owner, address(this), shares);
        _mint(receiver, tokenId);

        emit WithdrawalRequested(tokenId, shares, receiver, owner);
    }

    /// @notice Claims a completed withdrawal request.
    /// @param tokenId The withdrawal NFT id.
    /// @param maxIterations The maximum number of iterations to claim.
    function claim(uint256 tokenId, uint256 maxIterations) external {
        WithdrawalRequest memory request = _requests[tokenId];

        (uint256 assetsToClaim, uint256 sharesToClaim) = _claimable(tokenId, maxIterations);

        // update in storage for next claims
        _requests[tokenId].claimedShares = request.claimedShares + sharesToClaim;

        // transfer out claimed assets
        IERC20(SYM_RE.asset()).safeTransfer(request.receiver, assetsToClaim);

        emit WithdrawalClaimed(tokenId, assetsToClaim);
    }

    /// @notice Returns the claimable assets and shares for a withdrawal request.
    /// @param tokenId The withdrawal NFT id.
    /// @return assetsToClaim The claimable assets.
    /// @return sharesToClaim The claimable shares.
    function claimable(uint256 tokenId) external view returns (uint256 assetsToClaim, uint256 sharesToClaim) {
        (assetsToClaim, sharesToClaim) = _claimable(tokenId, type(uint256).max);
    }

    /// @notice Fills a partial withdrawal request.
    /// @param amount The amount of assets to fill.
    function fill(uint256 amount) external {
        uint256 shares = SYM_RE.convertToShares(amount);
        if (shares > totalRequested - totalFilled) {
            revert TooManySharesToFill();
        }

        // if no shares to fill, return
        if (shares == 0) {
            return;
        }

        IERC20 asset = IERC20(SYM_RE.asset());
        asset.safeTransferFrom(msg.sender, address(SYM_RE), amount);

        uint256 totalShares = SYM_RE.totalSupply();
        uint256 totalAssets = SYM_RE.previewRedeem(totalShares);
        SYM_RE.redeem(shares, address(this), address(this));

        // if share price has changed, update the checkpoint
        if ( _latestTotalAssets * totalShares != _latestTotalShares * totalAssets) {
            SharePriceCheckpoint memory checkpoint =
                SharePriceCheckpoint({filledShares: totalFilled, totalAssets: _latestTotalAssets, totalShares: _latestTotalShares});

            _sharePriceCheckpoints.push(checkpoint);
            _cumFilledSharesToSharePrice.push(checkpoint.filledShares, _sharePriceCheckpoints.length);

            _latestTotalAssets = totalAssets;
            _latestTotalShares = totalShares;
        }

        totalFilled += shares;
    }

    /// @notice Returns the claimable assets and shares for a withdrawal request.
    /// @param tokenId The withdrawal NFT id.
    /// @param maxIterations The maximum number of iterations to claim.
    /// @return assetsToClaim The claimable assets.
    /// @return sharesToClaim The claimable shares.
    function _claimable(uint256 tokenId, uint256 maxIterations)
        internal
        view
        returns (uint256 assetsToClaim, uint256 sharesToClaim)
    {
        WithdrawalRequest memory request = _requests[tokenId];

        if (request.claimedShares == request.shares) {
            return (0, 0);
        }

        uint256 cumClaimedShares = request.prevRequestSum + request.claimedShares;

        for (uint256 i = 0; i < maxIterations; i++) {
            if (cumClaimedShares == totalFilled) {
                break;
            }

            uint256 filledShares = totalFilled;
            uint256 totalAssets = _latestTotalAssets;
            uint256 totalShares = _latestTotalShares;

            uint256 checkpointIndex = _cumFilledSharesToSharePrice.lowerLookup(cumClaimedShares + 1);
            if (checkpointIndex != 0) {
                SharePriceCheckpoint memory checkpoint = _sharePriceCheckpoints[checkpointIndex - 1];
                filledShares = checkpoint.filledShares;
                totalAssets = checkpoint.totalAssets;
                totalShares = checkpoint.totalShares;
            }

            uint256 requestClaimedShares = cumClaimedShares - request.prevRequestSum;
            uint256 sharesToFill = Math.min(filledShares - cumClaimedShares, request.shares - requestClaimedShares);

            if (sharesToFill == 0) {
                break;
            }

            assetsToClaim += Math.mulDiv(sharesToFill, totalAssets, totalShares);
            cumClaimedShares += sharesToFill;
            sharesToClaim += sharesToFill;
        }

        return (assetsToClaim, sharesToClaim);
    }
}