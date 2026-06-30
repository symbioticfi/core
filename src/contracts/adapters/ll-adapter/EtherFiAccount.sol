// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Account} from "./common/Account.sol";

import {IEtherFiAccount} from "../../../interfaces/adapters/ll-adapter/etherfi/IEtherFiAccount.sol";
import {IEtherFiLiquidityPool} from "../../../interfaces/adapters/ll-adapter/etherfi/IEtherFiLiquidityPool.sol";
import {IEtherFiRedemptionManager} from "../../../interfaces/adapters/ll-adapter/etherfi/IEtherFiRedemptionManager.sol";
import {
    IEtherFiWithdrawRequestNFT
} from "../../../interfaces/adapters/ll-adapter/etherfi/IEtherFiWithdrawRequestNFT.sol";
import {IWETH} from "../../../interfaces/adapters/ll-adapter/etherfi/IWETH.sol";
import {IWeETH} from "../../../interfaces/adapters/ll-adapter/etherfi/IWeETH.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title EtherFiAccount
/// @notice Account for ether.fi weETH redemptions.
abstract contract EtherFiAccount is Account, IEtherFiAccount {
    using SafeERC20 for IERC20;

    /* IMMUTABLES */

    /// @inheritdoc IEtherFiAccount
    address public immutable WITHDRAW_REQUEST_NFT;
    /// @inheritdoc IEtherFiAccount
    address public immutable REDEMPTION_MANAGER;
    /// @inheritdoc IEtherFiAccount
    address public immutable LIQUIDITY_POOL;
    /// @inheritdoc IEtherFiAccount
    address public immutable EETH;
    /// @inheritdoc IEtherFiAccount
    address public immutable WETH;

    /* STATE VARIABLES */

    /// @inheritdoc IEtherFiAccount
    uint64[] public requestIds;

    /* CONSTRUCTOR */

    /// @notice Creates the ether.fi account implementation.
    constructor(
        address eETH,
        address weth,
        address oracle,
        address factory,
        address liquidityPool,
        address tokenToRedeem,
        address redemptionManager,
        address cowSwapSettlement,
        address withdrawRequestNft
    ) Account(oracle, factory, tokenToRedeem, cowSwapSettlement) {
        WITHDRAW_REQUEST_NFT = withdrawRequestNft;
        REDEMPTION_MANAGER = redemptionManager;
        LIQUIDITY_POOL = liquidityPool;
        EETH = eETH;
        WETH = weth;
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc IEtherFiAccount
    function pendingAssets() public view returns (uint256 assets) {
        uint256 length = requestIds.length;
        for (uint256 i; i < length; ++i) {
            IEtherFiWithdrawRequestNFT.WithdrawRequest memory request =
                IEtherFiWithdrawRequestNFT(WITHDRAW_REQUEST_NFT).getRequest(requestIds[i]);
            if (request.isValid) {
                uint256 requestAssets = request.amountOfEEth;
                uint256 shareAssets = IEtherFiLiquidityPool(LIQUIDITY_POOL).amountForShare(request.shareOfEEth);
                uint256 fee = uint256(request.feeGwei) * 1 gwei;

                requestAssets = requestAssets < shareAssets ? requestAssets : shareAssets;
                if (requestAssets > fee) {
                    assets += _redemptionTokenToAssets(WETH, requestAssets - fee);
                }
            }
        }
    }

    /* PUBLIC FUNCTIONS */

    /// @inheritdoc IEtherFiAccount
    function claimWithdraw(uint256 requestId) public {
        uint256 ethBalanceBefore = address(this).balance;
        IEtherFiWithdrawRequestNFT(WITHDRAW_REQUEST_NFT).claimWithdraw(requestId);
        _wrapClaimedEth(ethBalanceBefore);

        uint256 length = requestIds.length;
        for (uint256 i; i < length; ++i) {
            if (requestIds[i] == requestId) {
                requestIds[i] = requestIds[length - 1];
                requestIds.pop();
                return;
            }
        }
    }

    /// @inheritdoc IEtherFiAccount
    function onERC721Received(address, address, uint256, bytes calldata) public pure returns (bytes4) {
        return IEtherFiAccount.onERC721Received.selector;
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Returns pending request value in vault assets.
    function _totalAssets() internal view override returns (uint256) {
        return pendingAssets();
    }

    /// @dev Uses no-fee instant redemption into WETH when available, otherwise queues a WETH-backed withdrawal.
    function _sync() internal override {
        uint256 length = requestIds.length;
        for (uint256 i = length; i > 0; --i) {
            uint256 index = i - 1;
            uint64 requestId = requestIds[index];
            uint256 ethBalanceBefore = address(this).balance;
            try IEtherFiWithdrawRequestNFT(WITHDRAW_REQUEST_NFT).claimWithdraw(requestId) {
                _wrapClaimedEth(ethBalanceBefore);
                --length;
                requestIds[index] = requestIds[length];
                requestIds.pop();
            } catch {}
        }

        uint256 amountToRedeem = IERC20(TOKEN_TO_REDEEM).balanceOf(address(this));
        if (amountToRedeem == 0) {
            return;
        }

        address outputToken = IEtherFiRedemptionManager(REDEMPTION_MANAGER).ETH_ADDRESS();
        (,, uint16 exitFeeInBps,) = IEtherFiRedemptionManager(REDEMPTION_MANAGER).tokenToRedemptionInfo(outputToken);
        if (
            exitFeeInBps == 0
                && IEtherFiRedemptionManager(REDEMPTION_MANAGER)
                    .canRedeem(IWeETH(TOKEN_TO_REDEEM).getEETHByWeETH(amountToRedeem), outputToken)
        ) {
            uint256 ethBalanceBefore = address(this).balance;
            IERC20(TOKEN_TO_REDEEM).forceApprove(REDEMPTION_MANAGER, amountToRedeem);
            try IEtherFiRedemptionManager(REDEMPTION_MANAGER).redeemWeEth(amountToRedeem, address(this), outputToken) {
                uint256 claimed = address(this).balance - ethBalanceBefore;
                if (claimed > 0) {
                    IWETH(WETH).deposit{value: claimed}();
                    return;
                }
            } catch {}

            amountToRedeem = IERC20(TOKEN_TO_REDEEM).balanceOf(address(this));
            if (amountToRedeem == 0) {
                revert InstantRedemptionUnavailable();
            }
        }

        uint256 eETHAmount = IWeETH(TOKEN_TO_REDEEM).unwrap(amountToRedeem);
        IERC20(EETH).forceApprove(LIQUIDITY_POOL, eETHAmount);
        requestIds.push(uint64(IEtherFiLiquidityPool(LIQUIDITY_POOL).requestWithdraw(address(this), eETHAmount)));
    }

    /// @dev Wraps ETH received from queued withdrawal claims into WETH.
    function _wrapClaimedEth(uint256 ethBalanceBefore) internal {
        uint256 claimed = address(this).balance - ethBalanceBefore;
        if (claimed == 0) {
            return;
        }

        IWETH(WETH).deposit{value: claimed}();
    }

    /* INITIALIZATION */

    /// @dev Initializes the account for an adapter and vault.
    function _initialize(uint64 initialVersion, address initOwner, bytes memory data) internal override {
        super._initialize(initialVersion, initOwner, data);
        if (_asset != WETH) {
            revert InvalidAsset();
        }
    }

    /* RECEIVE */

    receive() external payable {}
}
