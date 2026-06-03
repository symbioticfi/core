// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {Account} from "../Account.sol";
import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";

import {IWeETHAccount} from "../../../../interfaces/adapters/ll-adapter/etherfi/IWeETHAccount.sol";
import {
    IEtherFiLiquidityPool as ILiquidityPool
} from "../../../../interfaces/adapters/ll-adapter/etherfi/IEtherFiLiquidityPool.sol";
import {
    IEtherFiRedemptionManager as IRedemptionManager
} from "../../../../interfaces/adapters/ll-adapter/etherfi/IEtherFiRedemptionManager.sol";
import {
    IEtherFiWithdrawRequestNFT as IWithdrawRequestNFT
} from "../../../../interfaces/adapters/ll-adapter/etherfi/IEtherFiWithdrawRequestNFT.sol";
import {IOracle} from "../../../../interfaces/adapters/ll-adapter/IOracle.sol";
import {IWETH} from "../../../../interfaces/adapters/ll-adapter/etherfi/IWETH.sol";
import {IWeETH} from "../../../../interfaces/adapters/ll-adapter/etherfi/IWeETH.sol";
import {IWstETH} from "../../../../interfaces/adapters/ll-adapter/lido/IWstETH.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract weETH_Account is Account, IWeETHAccount {
    using SafeERC20 for IERC20;
    using Math for uint256;

    error InstantRedemptionUnavailable();

    address public immutable EETH;
    address public immutable WETH;
    address public immutable STETH;
    address public immutable WSTETH;
    address public immutable LIQUIDITY_POOL;
    address public immutable REDEMPTION_MANAGER;
    address public immutable WITHDRAW_REQUEST_NFT;

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
        WETH = weth;
        STETH = stETH;
        WSTETH = wstETH;
        LIQUIDITY_POOL = liquidityPool;
        REDEMPTION_MANAGER = redemptionManager;
        WITHDRAW_REQUEST_NFT = withdrawRequestNft;
    }

    function claimWithdraw(uint256 requestId) public {
        uint256 ethBalanceBefore = address(this).balance;
        IWithdrawRequestNFT(WITHDRAW_REQUEST_NFT).claimWithdraw(requestId);
        _wrapClaimedEth(ethBalanceBefore);
    }

    function _totalAssets() internal view override returns (uint256 assets) {
        assets = pendingAssets;

        if (_asset == WETH) {
            assets += _fromBase18Asset(IERC20(STETH).balanceOf(address(this)));
        } else if (_asset == STETH) {
            assets += _fromBase18Asset(IERC20(WETH).balanceOf(address(this)));
        }
    }

    function _sync() internal override {
        uint256 amountToRedeem = IERC20(TOKEN_TO_REDEEM).balanceOf(address(this));
        if (amountToRedeem == 0) {
            return;
        }

        if (_tryInstantRedeem(amountToRedeem, STETH)) {
            if (_asset == WSTETH) {
                _wrapAllStethToWsteth();
            }
            return;
        }

        _requestWithdrawal(amountToRedeem, IOracle(ORACLE).getPrice());
    }

    function _tryInstantRedeem(uint256 amountToRedeem, address outputToken) internal returns (bool) {
        IRedemptionManager manager = IRedemptionManager(REDEMPTION_MANAGER);
        (,, uint16 exitFeeInBps,) = manager.tokenToRedemptionInfo(outputToken);
        if (exitFeeInBps > 0) {
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
        pendingAssets += _tokenToRedeemToAssets(amountToRedeem, price);

        uint256 eETHAmount = IWeETH(TOKEN_TO_REDEEM).unwrap(amountToRedeem);
        IERC20(EETH).forceApprove(LIQUIDITY_POOL, eETHAmount);
        ILiquidityPool(LIQUIDITY_POOL).requestWithdraw(address(this), eETHAmount);
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

    function _fromBase18Asset(uint256 amount) internal view returns (uint256) {
        return amount.mulDiv(_unit, 1e18);
    }

    receive() external payable {}
}

contract weETH_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}
