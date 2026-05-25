// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

// import {IVaultSnapshotRewards} from "../../interfaces/vault/IVaultSnapshotRewards.sol";
import {UniversalDelegator} from "../delegator/UniversalDelegator.sol";
import {VaultV2} from "./VaultV2.sol";
import {IWithdrawalQueue} from "../../interfaces/vault/IWithdrawalQueue.sol";

/// @title Withdrawal Queue
/// @notice Holds pending share withdrawal requests as ERC721 positions.
contract WithdrawalQueue is ERC721Upgradeable, IWithdrawalQueue {
    using SafeERC20 for IERC4626;
    using SafeERC20 for IERC20;
    using Math for uint256;
    using Checkpoints for Checkpoints.Trace256;

    uint256 internal constant SHARE_PRICE_TOLERANCE_DECIMALS = 7;

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
    /// @dev Share price checkpoints.
    SharePriceCheckpoint[] internal _sharePriceCheckpoints;
    /// @dev Cumulative shares filled to share price.
    Checkpoints.Trace256 internal _totalFilledSharesToSharePrice;
    /// @inheritdoc IWithdrawalQueue
    mapping(uint256 tokenId => WithdrawalRequest) public requests;

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
        return IERC4626(vault).convertToAssets(pendingShares());
    }

    /// @inheritdoc IWithdrawalQueue
    function pendingShares() public view returns (uint256) {
        return totalRequested - totalFilled;
    }

    /// @inheritdoc IWithdrawalQueue
    function claimable(uint256 tokenId, uint256 maxIterations)
        public
        view
        returns (uint256 assetsClaimed, uint256 sharesClaimed)
    {
        WithdrawalRequest storage request = requests[tokenId];

        if (request.claimedShares == request.shares) {
            return (0, 0);
        }

        uint256 maxSharesToClaim = Math.min(
            request.shares - request.claimedShares,
            totalFilled.saturatingSub(request.prevRequestSum + request.claimedShares)
        );
        uint256 cumClaimedShares = request.prevRequestSum + request.claimedShares;
        uint32 checkpointIndex = uint32(_totalFilledSharesToSharePrice.upperLookupRecent(cumClaimedShares));
        uint256 virtualShares = VaultV2(vault).virtualShares();

        for (; maxSharesToClaim > 0 && maxIterations > 0; --maxIterations) {
            uint256 curRequestShares = maxSharesToClaim;
            if (_totalFilledSharesToSharePrice.length() > checkpointIndex) {
                curRequestShares = Math.min(
                    _totalFilledSharesToSharePrice.at(checkpointIndex)._key - cumClaimedShares, maxSharesToClaim
                );
            }
            SharePriceCheckpoint storage checkpoint = _sharePriceCheckpoints[checkpointIndex++];
            assetsClaimed += curRequestShares.mulDiv(checkpoint.totalAssets + 1, checkpoint.totalShares + virtualShares);
            cumClaimedShares += curRequestShares;
            maxSharesToClaim -= curRequestShares;
        }

        sharesClaimed = cumClaimedShares - request.prevRequestSum - request.claimedShares;
    }

    /* PUBLIC FUNCTIONS */

    /// @inheritdoc IWithdrawalQueue
    function requestWithdraw(uint256 shares, address receiver) public returns (uint256 tokenId) {
        if (shares == 0) {
            revert ZeroShares();
        }

        IERC4626(vault).safeTransferFrom(msg.sender, address(this), shares);

        tokenId = _nextTokenId++;
        requests[tokenId] = WithdrawalRequest({shares: shares, claimedShares: 0, prevRequestSum: totalRequested});
        totalRequested += shares;

        _safeMint(receiver, tokenId);

        UniversalDelegator(VaultV2(vault).delegator()).onWithdrawRequest();

        emit RequestWithdraw(msg.sender, receiver, shares, tokenId);
    }

    /// @inheritdoc IWithdrawalQueue
    function claim(uint256 tokenId, uint256 maxIterations)
        public
        returns (uint256 assetsClaimed, uint256 sharesClaimed)
    {
        (assetsClaimed, sharesClaimed) = claimable(tokenId, maxIterations);

        requests[tokenId].claimedShares += sharesClaimed;

        IERC20(IERC4626(vault).asset()).safeTransfer(ownerOf(tokenId), assetsClaimed);

        emit Claim(tokenId, assetsClaimed, sharesClaimed);
    }

    /// @inheritdoc IWithdrawalQueue
    function fill() public {
        uint256 shares = Math.min(pendingShares(), VaultV2(vault).maxRedeem(address(this)));
        if (shares == 0) {
            return;
        }

        // Update the checkpoint when price decreases or increases past tolerance.
        uint256 totalShares = IERC4626(vault).totalSupply();
        uint256 totalAssets = IERC4626(vault).totalAssets();
        uint256 virtualShares = VaultV2(vault).virtualShares();
        SharePriceCheckpoint storage lastCheckpoint = _sharePriceCheckpoints[_sharePriceCheckpoints.length - 1];

        uint256 sharePriceScale = 10 ** IERC4626(vault).decimals();
        uint256 lastSharePrice =
            sharePriceScale.mulDiv(lastCheckpoint.totalAssets + 1, lastCheckpoint.totalShares + virtualShares);
        uint256 newSharePrice = sharePriceScale.mulDiv(totalAssets + 1, totalShares + virtualShares);
        if (
            newSharePrice < lastSharePrice
                || newSharePrice - lastSharePrice
                    >= 10
                        ** (uint256(IERC20Metadata(IERC4626(vault).asset()).decimals()))
                        .saturatingSub(SHARE_PRICE_TOLERANCE_DECIMALS)
        ) {
            _totalFilledSharesToSharePrice.push(totalFilled, _sharePriceCheckpoints.length);
            _sharePriceCheckpoints.push(SharePriceCheckpoint(totalAssets, totalShares));
        }

        uint256 amount = IERC4626(vault).redeem(shares, address(this), address(this));
        totalFilled += shares;

        emit Fill(amount, shares);
    }

    /* INITIALIZE */

    /// @dev Initialize withdrawal queue metadata and bind it to the calling vault.
    function initialize() public initializer {
        __ERC721_init("Withdrawal Queue", "WQ");

        vault = msg.sender;
        _sharePriceCheckpoints.push(SharePriceCheckpoint({totalAssets: 1, totalShares: VaultV2(vault).virtualShares()}));
    }
}
