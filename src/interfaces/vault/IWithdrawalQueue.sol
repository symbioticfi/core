// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IMigratableEntity} from "../common/IMigratableEntity.sol";
import {IMulticallable} from "../common/IMulticallable.sol";

import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

uint64 constant WITHDRAWAL_QUEUE_VERSION = 1;

/**
 * @title IWithdrawalQueue
 * @notice Interface for the WithdrawalQueue contract.
 */
interface IWithdrawalQueue is IMigratableEntity, IERC721Metadata, IMulticallable {
    /* STRUCTS */

    /**
     * @notice A pending withdrawal request.
     * @param shares Vault shares requested for withdrawal.
     * @param sharesClaimed Request shares already claimed.
     * @param prevRequestSum Cumulative requested shares before this request.
     */
    struct WithdrawalRequest {
        uint256 shares;
        uint256 sharesClaimed;
        uint256 prevRequestSum;
    }

    /* ERRORS */

    /**
     * @notice Reverts when a request is made by a non-vault account.
     */
    error NotVault();

    /**
     * @notice Reverts when a request is made with zero shares.
     */
    error ZeroShares();

    /* EVENTS */

    /**
     * @notice Emitted when a withdrawal request is created.
     * @param requester Account that requested the withdrawal.
     * @param receiver Account that received the withdrawal NFT.
     * @param shares Vault shares requested for withdrawal.
     * @param tokenId Withdrawal NFT id.
     */
    event RequestRedeem(address indexed requester, address indexed receiver, uint256 shares, uint256 indexed tokenId);

    /**
     * @notice Emitted when a withdrawal request is claimed.
     * @param tokenId Withdrawal NFT id.
     * @param assetsClaimed Assets claimed.
     * @param sharesClaimed Request shares claimed.
     */
    event Claim(uint256 indexed tokenId, uint256 assetsClaimed, uint256 sharesClaimed);

    /**
     * @notice Emitted when pending withdrawal requests are filled.
     * @param assets Assets used to fill the queue.
     * @param shares Vault shares filled.
     */
    event Fill(uint256 assets, uint256 shares);

    /* FUNCTIONS */

    /**
     * @notice Returns the ERC4626 vault accepted by the queue.
     * @return vaultToken ERC4626 vault address.
     */
    function vault() external view returns (address vaultToken);

    /**
     * @notice Total vault shares requested for withdrawal.
     * @return requested Total requested shares.
     */
    function totalRequested() external view returns (uint256 requested);

    /**
     * @notice Returns the request details for a withdrawal NFT.
     * @param tokenId Withdrawal NFT id.
     * @return shares Vault shares requested for withdrawal.
     * @return sharesClaimed Request shares already claimed.
     * @return prevRequestSum Cumulative requested shares before this request.
     */
    function requests(uint256 tokenId)
        external
        view
        returns (uint256 shares, uint256 sharesClaimed, uint256 prevRequestSum);

    /**
     * @notice Total withdrawal requests created.
     * @return count Total requests.
     */
    function totalRequests() external view returns (uint256 count);

    /**
     * @notice Total vault shares filled.
     * @return filled Total filled shares.
     */
    function totalFilled() external view returns (uint256 filled);

    /**
     * @notice Returns the pending shares in the queue.
     * @return shares Pending shares.
     */
    function pendingShares() external view returns (uint256 shares);

    /**
     * @notice Returns the pending assets in the queue.
     * @return assets Pending assets.
     */
    function pendingAssets() external view returns (uint256 assets);

    /**
     * @notice Returns whether a withdrawal request has been fully claimed.
     * @param tokenId Withdrawal NFT id.
     * @return claimed Whether the request has been fully claimed.
     */
    function isClaimed(uint256 tokenId) external view returns (bool claimed);

    /**
     * @notice Returns the claimable assets and shares for a withdrawal request.
     * @param tokenId Withdrawal NFT id.
     * @return assetsClaimed Claimable assets.
     * @return sharesClaimed Claimable shares.
     */
    function claimable(uint256 tokenId) external view returns (uint256 assetsClaimed, uint256 sharesClaimed);

    /**
     * @notice Transfers vault shares into the queue and mints a withdrawal NFT.
     * @param shares Vault shares to request for withdrawal.
     * @param receiver Address that receives the withdrawal NFT.
     * @return tokenId Minted withdrawal NFT id.
     */
    function requestRedeem(uint256 shares, address receiver) external returns (uint256 tokenId);

    /**
     * @notice Claims a withdrawal request.
     * @param tokenId Withdrawal NFT id.
     * @return assetsClaimed Assets claimed.
     * @return sharesClaimed Request shares claimed.
     */
    function claim(uint256 tokenId) external returns (uint256 assetsClaimed, uint256 sharesClaimed);

    /**
     * @notice Fills pending withdrawal requests with available vault assets.
     */
    function fill() external returns (uint256 assets, uint256 shares);
}
