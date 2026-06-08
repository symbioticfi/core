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
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title EtherFiAccount
/// @notice Account for ether.fi weETH redemptions.
abstract contract EtherFiAccount is Account, IEtherFiAccount {
    using SafeERC20 for IERC20;
    using Math for uint256;

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
    uint256 public pendingAssets;
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

    /* PUBLIC FUNCTIONS */

    /// @inheritdoc IEtherFiAccount
    function claimWithdraw(uint256 requestId) public {
        uint256 ethBalanceBefore = address(this).balance;
        IEtherFiWithdrawRequestNFT(WITHDRAW_REQUEST_NFT).claimWithdraw(requestId);
        if (_wrapClaimedEth(ethBalanceBefore)) {
            for (uint256 i; i < requestIds.length; ++i) {
                if (requestIds[i] == requestId) {
                    requestIds[i] = requestIds[requestIds.length - 1];
                    requestIds.pop();
                    return;
                }
            }
        }
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Returns pending request value in vault assets.
    function _totalAssets() internal view override returns (uint256 assets) {
        assets = pendingAssets;
    }

    /// @dev Uses no-fee instant redemption into WETH when available, otherwise queues a WETH-backed withdrawal.
    function _sync() internal override {
        for (uint256 i = requestIds.length; i > 0; --i) {
            uint256 ethBalanceBefore = address(this).balance;
            try IEtherFiWithdrawRequestNFT(WITHDRAW_REQUEST_NFT).claimWithdraw(requestIds[i - 1]) {
                if (_wrapClaimedEth(ethBalanceBefore)) {
                    requestIds[i - 1] = requestIds[requestIds.length - 1];
                    requestIds.pop();
                }
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
            IEtherFiRedemptionManager(REDEMPTION_MANAGER).redeemWeEth(amountToRedeem, address(this), outputToken);

            uint256 claimed = address(this).balance - ethBalanceBefore;
            if (claimed == 0) {
                revert InstantRedemptionUnavailable();
            }

            IWETH(WETH).deposit{value: address(this).balance}();
            return;
        }

        pendingAssets += _tokenToRedeemToAssets(amountToRedeem);
        uint256 eETHAmount = IWeETH(TOKEN_TO_REDEEM).unwrap(amountToRedeem);
        IERC20(EETH).forceApprove(LIQUIDITY_POOL, eETHAmount);
        requestIds.push(uint64(IEtherFiLiquidityPool(LIQUIDITY_POOL).requestWithdraw(address(this), eETHAmount)));
    }

    /// @dev Wraps ETH received from queued withdrawal claims into WETH.
    function _wrapClaimedEth(uint256 ethBalanceBefore) internal returns (bool wrapped) {
        uint256 claimed = address(this).balance - ethBalanceBefore;
        if (claimed == 0) {
            return false;
        }

        IWETH(WETH).deposit{value: address(this).balance}();

        uint256 claimedAssets = claimed.mulDiv(_unit, 1e18);
        pendingAssets = pendingAssets > claimedAssets ? pendingAssets - claimedAssets : 0;
        wrapped = true;
    }

    /* RECEIVE */

    receive() external payable {}
}
