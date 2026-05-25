// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

// import {IVaultSnapshotRewards} from "../../interfaces/vault/IVaultSnapshotRewards.sol";
import {UniversalDelegator} from "../delegator/UniversalDelegator.sol";
import {VaultV2} from "./VaultV2.sol";
import {IWithdrawalQueue} from "../../interfaces/vault/IWithdrawalQueue.sol";

/// @title Withdrawal Queue
/// @notice Holds pending share withdrawal requests as ERC721 positions.
contract WithdrawalQueue is ERC721Upgradeable, IWithdrawalQueue {
    using Checkpoints for Checkpoints.Trace256;
    using SafeERC20 for IERC20;
    using SafeCast for uint256;
    using Math for uint256;

    /* STATE VARIABLES */

    /// @inheritdoc IWithdrawalQueue
    address public vault;
    /// @inheritdoc IWithdrawalQueue
    uint256 public totalRequested;
    /// @inheritdoc IWithdrawalQueue
    mapping(uint256 tokenId => WithdrawalRequest) public requests;

    /// @dev The next withdrawal NFT id.
    uint256 internal _nextTokenId;
    /// @dev Cumulative filled shares to packed fill index and cumulative assets.
    Checkpoints.Trace256 internal _cumulSharesToCumulAssets;

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

    /* CONSTRUCTOR */

    constructor() {
        _disableInitializers();
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc IWithdrawalQueue
    function totalFilled() public view returns (uint256) {
        return _cumulSharesToCumulAssets.at(uint32(_cumulSharesToCumulAssets.length() - 1))._key;
    }

    /// @inheritdoc IWithdrawalQueue
    function pendingShares() public view returns (uint256) {
        return totalRequested - totalFilled();
    }

    /// @inheritdoc IWithdrawalQueue
    function pendingAssets() public view returns (uint256) {
        return IERC4626(vault).previewRedeem(pendingShares());
    }

    /// @inheritdoc IWithdrawalQueue
    function claimable(uint256 tokenId) public view returns (uint256 assets, uint256 shares) {
        WithdrawalRequest storage request = requests[tokenId];

        if (request.claimedShares == request.shares) {
            return (0, 0);
        }

        uint256 startShares = request.prevRequestSum + request.claimedShares;
        uint256 endShares = Math.min(request.prevRequestSum + request.shares, totalFilled());
        shares = endShares.saturatingSub(startShares);
        if (shares == 0) {
            return (0, 0);
        }

        uint32 pos = uint32(_cumulSharesToCumulAssets.upperLookupRecent(startShares) >> 224);
        Checkpoints.Checkpoint256 memory checkpoint = _cumulSharesToCumulAssets.at(pos);
        Checkpoints.Checkpoint256 memory nextCheckpoint = _cumulSharesToCumulAssets.at(pos + 1);
        uint256 startAssets = uint224(checkpoint._value)
            + (startShares - checkpoint._key)
            .mulDiv(uint224(nextCheckpoint._value) - uint224(checkpoint._value), nextCheckpoint._key - checkpoint._key);

        pos = uint32(_cumulSharesToCumulAssets.upperLookupRecent(endShares - 1) >> 224);
        checkpoint = _cumulSharesToCumulAssets.at(pos);
        nextCheckpoint = _cumulSharesToCumulAssets.at(pos + 1);
        uint256 endAssets = uint224(checkpoint._value)
            + (endShares - checkpoint._key)
            .mulDiv(uint224(nextCheckpoint._value) - uint224(checkpoint._value), nextCheckpoint._key - checkpoint._key);

        assets = endAssets - startAssets;
    }

    /* PUBLIC FUNCTIONS */

    /// @inheritdoc IWithdrawalQueue
    function requestRedeem(uint256 shares, address receiver) public returns (uint256 tokenId) {
        if (shares == 0) {
            revert ZeroShares();
        }

        IERC20(vault).safeTransferFrom(msg.sender, address(this), shares);

        tokenId = _nextTokenId++;
        requests[tokenId] = WithdrawalRequest({shares: shares, claimedShares: 0, prevRequestSum: totalRequested});
        totalRequested += shares;

        _mint(receiver, tokenId);

        UniversalDelegator(VaultV2(vault).delegator()).sweepPending();

        emit RequestWithdraw(msg.sender, receiver, shares, tokenId);
    }

    /// @inheritdoc IWithdrawalQueue
    function claim(uint256 tokenId) public returns (uint256 assetsClaimed, uint256 sharesClaimed) {
        (assetsClaimed, sharesClaimed) = claimable(tokenId);

        requests[tokenId].claimedShares += sharesClaimed;

        IERC20(IERC4626(vault).asset()).safeTransfer(ownerOf(tokenId), assetsClaimed);

        emit Claim(tokenId, assetsClaimed, sharesClaimed);
    }

    /// @inheritdoc IWithdrawalQueue
    function fill() public returns (uint256 assets, uint256 shares) {
        shares = pendingShares();
        if (shares == 0) {
            return (0, 0);
        }
        shares = Math.min(shares, IERC4626(vault).previewDeposit(VaultV2(vault).withdrawable()));
        if (shares == 0) {
            return (0, 0);
        }

        assets = IERC4626(vault).redeem(shares, address(this), address(this));

        _cumulSharesToCumulAssets.push(
            totalFilled() + shares,
            _cumulSharesToCumulAssets.length() << 224
                | (uint224(_cumulSharesToCumulAssets.latest()) + assets).toUint224()
        );

        emit Fill(assets, shares);
    }

    /* INITIALIZE */

    /// @dev Initialize withdrawal queue metadata and bind it to the calling vault.
    function initialize() public initializer {
        __ERC721_init("Withdrawal Queue", "WQ");

        vault = msg.sender;

        _cumulSharesToCumulAssets.push(0, 0);
    }
}
