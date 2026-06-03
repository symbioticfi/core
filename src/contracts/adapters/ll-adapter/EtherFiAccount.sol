// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {Account} from "./Account.sol";

import {IEtherFiAccount} from "../../../interfaces/adapters/ll-adapter/etherfi/IEtherFiAccount.sol";
import {IEtherFiLiquidityPool} from "../../../interfaces/adapters/ll-adapter/etherfi/IEtherFiLiquidityPool.sol";
import {IEtherFiRedemptionManager} from "../../../interfaces/adapters/ll-adapter/etherfi/IEtherFiRedemptionManager.sol";
import {
    IEtherFiWithdrawRequestNFT
} from "../../../interfaces/adapters/ll-adapter/etherfi/IEtherFiWithdrawRequestNFT.sol";
import {IOracle} from "../../../interfaces/adapters/ll-adapter/IOracle.sol";
import {IWETH} from "../../../interfaces/adapters/ll-adapter/etherfi/IWETH.sol";
import {IWeETH} from "../../../interfaces/adapters/ll-adapter/etherfi/IWeETH.sol";
import {IWstETH} from "../../../interfaces/adapters/ll-adapter/lido/IWstETH.sol";

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
    address public immutable EETH;
    /// @inheritdoc IEtherFiAccount
    address public immutable LIQUIDITY_POOL;
    /// @inheritdoc IEtherFiAccount
    address public immutable REDEMPTION_MANAGER;
    /// @inheritdoc IEtherFiAccount
    address public immutable WITHDRAW_REQUEST_NFT;
    /// @inheritdoc IEtherFiAccount
    address public immutable STETH;
    /// @inheritdoc IEtherFiAccount
    address public immutable WSTETH;
    /// @inheritdoc IEtherFiAccount
    address public immutable WETH;

    /* STATE VARIABLES */

    /// @inheritdoc IEtherFiAccount
    uint256 public pendingAssets;

    /* CONSTRUCTOR */

    /// @notice Creates the ether.fi account implementation.
    constructor(
        address withdrawRequestNft,
        address redemptionManager,
        address liquidityPool,
        address tokenToRedeem,
        address factory,
        address oracle,
        address wstETH,
        address stETH,
        address eETH,
        address weth
    ) Account(factory, oracle, tokenToRedeem) {
        WITHDRAW_REQUEST_NFT = withdrawRequestNft;
        REDEMPTION_MANAGER = redemptionManager;
        LIQUIDITY_POOL = liquidityPool;
        WSTETH = wstETH;
        STETH = stETH;
        EETH = eETH;
        WETH = weth;
    }

    /* PUBLIC FUNCTIONS */

    /// @inheritdoc IEtherFiAccount
    function claimWithdraw(uint256 requestId) public {
        uint256 ethBalanceBefore = address(this).balance;
        IEtherFiWithdrawRequestNFT(WITHDRAW_REQUEST_NFT).claimWithdraw(requestId);
        _wrapClaimedEth(ethBalanceBefore);
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Returns pending requests plus held non-asset stETH/WETH value in vault assets.
    function _totalAssets() internal view override returns (uint256 assets) {
        assets = pendingAssets;

        if (_asset == WETH) {
            assets += _fromBase18Asset(IERC20(STETH).balanceOf(address(this)));
        } else if (_asset == STETH) {
            assets += _fromBase18Asset(IERC20(WETH).balanceOf(address(this)));
        }
    }

    /// @dev Uses no-fee instant redemption into stETH when available, otherwise queues a WETH-backed withdrawal.
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

    /// @dev Attempts an ether.fi instant redemption only when the configured exit fee is zero.
    function _tryInstantRedeem(uint256 amountToRedeem, address outputToken) internal returns (bool) {
        IEtherFiRedemptionManager manager = IEtherFiRedemptionManager(REDEMPTION_MANAGER);
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

    /// @dev Opens a delayed ether.fi withdrawal request from unwrapped eETH.
    function _requestWithdrawal(uint256 amountToRedeem, uint256 price) internal {
        pendingAssets += _tokenToRedeemToAssets(amountToRedeem, price);

        uint256 eETHAmount = IWeETH(TOKEN_TO_REDEEM).unwrap(amountToRedeem);
        IERC20(EETH).forceApprove(LIQUIDITY_POOL, eETHAmount);
        IEtherFiLiquidityPool(LIQUIDITY_POOL).requestWithdraw(address(this), eETHAmount);
    }

    /// @dev Wraps any instant redemption stETH proceeds into wstETH.
    function _wrapAllStethToWsteth() internal {
        uint256 stETHBalance = IERC20(STETH).balanceOf(address(this));
        if (stETHBalance == 0) {
            revert InstantRedemptionUnavailable();
        }

        IERC20(STETH).forceApprove(WSTETH, stETHBalance);
        IWstETH(WSTETH).wrap(stETHBalance);
    }

    /// @dev Wraps ETH received from queued withdrawal claims into WETH.
    function _wrapClaimedEth(uint256 ethBalanceBefore) internal {
        uint256 claimed = address(this).balance - ethBalanceBefore;
        if (claimed == 0) {
            return;
        }

        IWETH(WETH).deposit{value: claimed}();

        uint256 claimedAssets = _fromBase18Asset(claimed);
        pendingAssets = pendingAssets > claimedAssets ? pendingAssets - claimedAssets : 0;
    }

    /// @dev Converts an 18-decimal ETH-denominated amount into the vault asset decimals.
    function _fromBase18Asset(uint256 amount) internal view returns (uint256) {
        return amount.mulDiv(_unit, 1e18);
    }

    /* RECEIVE */

    receive() external payable {}
}
