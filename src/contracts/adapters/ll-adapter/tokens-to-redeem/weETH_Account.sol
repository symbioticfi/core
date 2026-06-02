// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {Account} from "../accounts/Account.sol";

import {IEtherFiLiquidityPool} from "../../../../interfaces/adapters/ll-adapter/accounts/IEtherFiLiquidityPool.sol";
import {
    IEtherFiRedemptionManager
} from "../../../../interfaces/adapters/ll-adapter/accounts/IEtherFiRedemptionManager.sol";
import {
    IEtherFiWithdrawRequestNFT
} from "../../../../interfaces/adapters/ll-adapter/accounts/IEtherFiWithdrawRequestNFT.sol";
import {IWETH} from "../../../../interfaces/adapters/ll-adapter/accounts/IWETH.sol";
import {IWeETH} from "../../../../interfaces/adapters/ll-adapter/accounts/IWeETH.sol";
import {IWstETH} from "../../../../interfaces/adapters/ll-adapter/accounts/IWstETH.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title weETH_Account
/// @notice ether.fi account for weETH redemptions.
contract weETH_Account is Account {
    using SafeERC20 for IERC20;

    address public immutable EETH;
    address public immutable LIQUIDITY_POOL;
    address public immutable REDEMPTION_MANAGER;
    address public immutable WITHDRAW_REQUEST_NFT;
    address public immutable STETH;
    address public immutable WSTETH;
    address public immutable WETH;

    uint256 public pendingAssets;

    constructor(
        address factory,
        address oracle,
        address weETH,
        address eETH,
        address liquidityPool,
        address redemptionManager,
        address withdrawRequestNft,
        address stETH,
        address wstETH,
        address weth
    ) Account(factory, oracle, weETH) {
        EETH = eETH;
        LIQUIDITY_POOL = liquidityPool;
        REDEMPTION_MANAGER = redemptionManager;
        WITHDRAW_REQUEST_NFT = withdrawRequestNft;
        STETH = stETH;
        WSTETH = wstETH;
        WETH = weth;
    }

    function claimWithdraw(uint256 requestId) public {
        uint256 ethBalanceBefore = address(this).balance;
        IEtherFiWithdrawRequestNFT(WITHDRAW_REQUEST_NFT).claimWithdraw(requestId);
        _wrapClaimedEth(ethBalanceBefore);
    }

    function _additionalAssets(address asset, uint256) internal view override returns (uint256 assets) {
        assets = pendingAssets;

        if (asset == WETH) {
            assets += _fromBase18Asset(IERC20(STETH).balanceOf(address(this)));
        } else if (asset == STETH) {
            assets += _fromBase18Asset(IERC20(WETH).balanceOf(address(this)));
        }
    }

    function _requestRedeem(uint256 amountToRedeem, uint256 price) internal override {
        if (_tryInstantRedeem(amountToRedeem, STETH)) {
            if (IERC4626(vault).asset() == WSTETH) {
                _wrapAllStethToWsteth();
            }
            return;
        }

        _requestWithdrawal(amountToRedeem, price);
    }

    function _tryInstantRedeem(uint256 amountToRedeem, address outputToken) internal returns (bool) {
        IEtherFiRedemptionManager manager = IEtherFiRedemptionManager(REDEMPTION_MANAGER);
        (,, uint16 exitFeeInBps,) = manager.tokenToRedemptionInfo(outputToken);
        if (exitFeeInBps != 0) {
            return false;
        }

        uint256 eETHAmount = IWeETH(TOKEN_TO_REDEEM).getEETHByWeETH(amountToRedeem);
        if (!manager.canRedeem(eETHAmount, outputToken)) {
            return false;
        }

        IERC20(TOKEN_TO_REDEEM).forceApprove(REDEMPTION_MANAGER, amountToRedeem);
        manager.redeemWeEth(amountToRedeem, address(this), outputToken);
        return true;
    }

    function _requestWithdrawal(uint256 amountToRedeem, uint256 price) internal {
        pendingAssets += _toAssets(amountToRedeem, price);

        uint256 eETHAmount = IWeETH(TOKEN_TO_REDEEM).unwrap(amountToRedeem);
        IERC20(EETH).forceApprove(LIQUIDITY_POOL, eETHAmount);
        IEtherFiLiquidityPool(LIQUIDITY_POOL).requestWithdraw(address(this), eETHAmount);
    }

    function _wrapAllStethToWsteth() internal {
        uint256 stETHBalance = IERC20(STETH).balanceOf(address(this));
        if (stETHBalance == 0) {
            revert InstantRedemptionUnavailable();
        }

        IERC20(STETH).forceApprove(WSTETH, stETHBalance);
        IWstETH(WSTETH).wrap(stETHBalance);
    }

    function _wrapClaimedEth(uint256 ethBalanceBefore) internal {
        uint256 claimed = address(this).balance - ethBalanceBefore;
        if (claimed == 0) {
            return;
        }

        IWETH(WETH).deposit{value: claimed}();

        uint256 claimedAssets = _fromBase18Asset(claimed);
        pendingAssets = pendingAssets > claimedAssets ? pendingAssets - claimedAssets : 0;
    }

    error InstantRedemptionUnavailable();

    receive() external payable {}
}
