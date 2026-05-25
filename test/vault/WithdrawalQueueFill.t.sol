// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";

import {WithdrawalQueue} from "../../src/contracts/vault/WithdrawalQueue.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract WithdrawalQueueFillToken is ERC20 {
    uint8 public tokenDecimals = 18;

    constructor() ERC20("Token", "TKN") {}

    function setDecimals(uint8 decimals_) external {
        tokenDecimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return tokenDecimals;
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}

contract WithdrawalQueueFillDelegator {
    address public vault;
    uint256 public totalAssetsValue;
    uint256 public syncCalls;

    constructor(address vault_) {
        vault = vault_;
    }

    function setTotalAssets(uint256 assets) external {
        totalAssetsValue = assets;
    }

    function totalAssets() external view returns (uint256) {
        return totalAssetsValue;
    }

    function onWithdrawRequest() external {
        ++syncCalls;
    }

    function onDeposit() external {}

    function sweepPending() external pure returns (uint256) {
        return 0;
    }
}

contract WithdrawalQueueFillVault is ERC20 {
    using Math for uint256;

    address public immutable collateral;
    address public delegatorContract;
    uint256 public managedAssets;
    uint256 public accrueInterestCalls;
    uint256 public withdrawableCalls;
    uint8 public shareDecimals = 18;
    uint256 public virtualSharesValue = 1;
    bool public isPreviewRedeemOverride;
    uint256 public previewRedeemOverride;
    bool public isVirtualPreviewRedeem;

    constructor(address collateral_) ERC20("Vault Share", "vTKN") {
        collateral = collateral_;
    }

    function setDelegator(address delegator_) external {
        delegatorContract = delegator_;
    }

    function setShareConfig(uint8 shareDecimals_, uint256 virtualShares_) external {
        shareDecimals = shareDecimals_;
        virtualSharesValue = virtualShares_;
    }

    function mintShares(address account, uint256 shares, uint256 assets) external {
        _mint(account, shares);
        managedAssets += assets;
    }

    function setManagedAssets(uint256 assets) external {
        managedAssets = assets;
    }

    function setPreviewRedeemOverride(uint256 assets) external {
        isPreviewRedeemOverride = true;
        previewRedeemOverride = assets;
    }

    function setVirtualPreviewRedeem(bool status) external {
        isVirtualPreviewRedeem = status;
    }

    function asset() external view returns (address) {
        return collateral;
    }

    function delegator() external view returns (address) {
        return delegatorContract;
    }

    function decimals() public view override returns (uint8) {
        return shareDecimals;
    }

    function virtualShares() external view returns (uint256) {
        return virtualSharesValue;
    }

    function totalAssets() external view returns (uint256) {
        return managedAssets;
    }

    function accrueInterest() external returns (uint256 performanceFeeShares, uint256 managementFeeShares) {
        ++accrueInterestCalls;
    }

    function previewRedeem(uint256 shares) external view returns (uint256) {
        if (isPreviewRedeemOverride) {
            return previewRedeemOverride;
        }
        if (isVirtualPreviewRedeem) {
            return shares.mulDiv(managedAssets + 1, totalSupply() + virtualSharesValue);
        }
        return totalSupply() == 0 ? 0 : shares.mulDiv(managedAssets, totalSupply());
    }

    function previewDeposit(uint256 assets) external view returns (uint256) {
        return managedAssets == 0 ? 0 : assets.mulDiv(totalSupply(), managedAssets);
    }

    function convertToAssets(uint256 shares) external view returns (uint256) {
        return totalSupply() == 0 ? 0 : shares.mulDiv(managedAssets, totalSupply());
    }

    function previewWithdraw(uint256 assets) external view returns (uint256) {
        return managedAssets == 0 ? 0 : assets.mulDiv(totalSupply(), managedAssets, Math.Rounding.Ceil);
    }

    function maxWithdraw(address) external view returns (uint256) {
        return WithdrawalQueueFillToken(collateral).balanceOf(address(this));
    }

    function maxRedeem(address owner) external view returns (uint256) {
        uint256 byLiquidity = managedAssets == 0
            ? 0
            : WithdrawalQueueFillToken(collateral).balanceOf(address(this)).mulDiv(totalSupply(), managedAssets);
        return Math.min(balanceOf(owner), byLiquidity);
    }

    function withdrawable() external returns (uint256) {
        ++withdrawableCalls;
        return WithdrawalQueueFillToken(collateral).balanceOf(address(this));
    }

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        assets = shares.mulDiv(managedAssets, totalSupply());
        _burn(owner, shares);
        managedAssets -= assets;
        WithdrawalQueueFillToken(collateral).transfer(receiver, assets);
    }

    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares) {
        shares = assets.mulDiv(totalSupply(), managedAssets, Math.Rounding.Ceil);
        _burn(owner, shares);
        managedAssets -= assets;
        WithdrawalQueueFillToken(collateral).transfer(receiver, assets);
    }
}

contract WithdrawalQueueFillTest is Test {
    using Math for uint256;

    address internal collateral;
    address internal vault;
    address internal delegator;
    address internal queue;

    address internal alice = address(0xA11CE);

    function setUp() public {
        collateral = address(new WithdrawalQueueFillToken());
        vault = address(new WithdrawalQueueFillVault(collateral));
        delegator = address(new WithdrawalQueueFillDelegator(vault));
        WithdrawalQueueFillVault(vault).setDelegator(delegator);

        queue = address(new WithdrawalQueue());
        vm.prank(vault);
        WithdrawalQueue(queue).initialize();
    }

    function test_RequestWithdrawNotifiesDelegatorAndFillRedeemsPendingShares() public {
        WithdrawalQueueFillToken(collateral).mint(vault, 100);
        WithdrawalQueueFillVault(vault).mintShares(alice, 100, 100);

        vm.startPrank(alice);
        WithdrawalQueueFillVault(vault).approve(queue, 100);
        WithdrawalQueue(queue).requestWithdraw(100, alice);
        vm.stopPrank();

        WithdrawalQueue(queue).fill();

        assertEq(WithdrawalQueueFillDelegator(delegator).syncCalls(), 1);
        assertEq(WithdrawalQueueFillVault(vault).accrueInterestCalls(), 0);
        assertEq(WithdrawalQueue(queue).totalFilled(), 100);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(queue), 100);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(vault), 0);
    }

    function test_PendingAssetsUsesPreviewRedeemOfPendingShares() public {
        uint256 shares = 100;

        WithdrawalQueueFillVault(vault).mintShares(alice, shares, 100);
        WithdrawalQueueFillVault(vault).setPreviewRedeemOverride(77);

        vm.startPrank(alice);
        WithdrawalQueueFillVault(vault).approve(queue, shares);
        WithdrawalQueue(queue).requestWithdraw(shares, alice);
        vm.stopPrank();

        assertEq(WithdrawalQueue(queue).pendingShares(), shares);
        assertEq(WithdrawalQueue(queue).pendingAssets(), 77);
    }

    function test_PendingAssetsUsesPreviewRedeemWhenVirtualSharesMakeItDiverge() public {
        uint256 virtualShares = 10;
        uint256 shares = 10;

        WithdrawalQueueFillVault(vault).setShareConfig(18, virtualShares);
        WithdrawalQueueFillVault(vault).setVirtualPreviewRedeem(true);
        WithdrawalQueueFillVault(vault).mintShares(alice, 100, 100);

        vm.startPrank(alice);
        WithdrawalQueueFillVault(vault).approve(queue, shares);
        WithdrawalQueue(queue).requestWithdraw(shares, alice);
        vm.stopPrank();

        assertEq(WithdrawalQueue(queue).pendingShares(), shares);
        assertEq(WithdrawalQueue(queue).pendingAssets(), 9);
        assertEq(WithdrawalQueueFillVault(vault).convertToAssets(shares), 10);
    }

    function test_FillWithNoPendingSharesDoesNotCallWithdrawable() public {
        (uint256 assets, uint256 shares) = WithdrawalQueue(queue).fill();

        assertEq(assets, 0);
        assertEq(shares, 0);
        assertEq(WithdrawalQueueFillVault(vault).withdrawableCalls(), 0);
    }

    function test_FillOnlyRedeemsAvailableSharesWhenVaultLiquidityIsLimited() public {
        uint256 shares = 100;
        uint256 liquidAssets = 40;

        WithdrawalQueueFillToken(collateral).mint(vault, liquidAssets);
        WithdrawalQueueFillVault(vault).mintShares(alice, shares, shares);

        vm.startPrank(alice);
        WithdrawalQueueFillVault(vault).approve(queue, shares);
        uint256 tokenId = WithdrawalQueue(queue).requestWithdraw(shares, alice);
        vm.stopPrank();

        WithdrawalQueue(queue).fill();

        assertEq(WithdrawalQueue(queue).totalFilled(), liquidAssets);
        assertEq(WithdrawalQueue(queue).pendingShares(), shares - liquidAssets);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(queue), liquidAssets);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(vault), 0);

        (uint256 assetsClaimed, uint256 sharesClaimed) = WithdrawalQueue(queue).claimable(tokenId, type(uint256).max);

        assertEq(assetsClaimed, liquidAssets);
        assertEq(sharesClaimed, liquidAssets);
    }

    function test_FillCapsWithdrawableAssetsAtHighSharePrice() public {
        uint256 shares = 100;
        uint256 managedAssets = 200;
        uint256 liquidAssets = 40;

        WithdrawalQueueFillToken(collateral).mint(vault, liquidAssets);
        WithdrawalQueueFillVault(vault).mintShares(alice, shares, managedAssets);

        vm.startPrank(alice);
        WithdrawalQueueFillVault(vault).approve(queue, shares);
        uint256 tokenId = WithdrawalQueue(queue).requestWithdraw(shares, alice);
        vm.stopPrank();

        WithdrawalQueue(queue).fill();

        assertEq(WithdrawalQueue(queue).totalFilled(), 20);
        assertEq(WithdrawalQueue(queue).pendingShares(), 80);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(queue), liquidAssets);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(vault), 0);

        (uint256 assetsClaimed, uint256 sharesClaimed) = WithdrawalQueue(queue).claimable(tokenId, type(uint256).max);
        uint256 expectedClaimableAssets =
            uint256(20).mulDiv(managedAssets + 1, shares + WithdrawalQueueFillVault(vault).virtualSharesValue());

        assertEq(assetsClaimed, expectedClaimableAssets);
        assertEq(sharesClaimed, 20);
    }

    function test_FillReturnsExactAssetsAndSharesWhenWithdrawableRoundsDownAtHighSharePrice() public {
        uint256 shares = 100;
        uint256 managedAssets = 200;
        uint256 liquidAssets = 41;

        WithdrawalQueueFillToken(collateral).mint(vault, liquidAssets);
        WithdrawalQueueFillVault(vault).mintShares(alice, shares, managedAssets);

        vm.startPrank(alice);
        WithdrawalQueueFillVault(vault).approve(queue, shares);
        WithdrawalQueue(queue).requestWithdraw(shares, alice);
        vm.stopPrank();

        (uint256 assetsFilled, uint256 sharesFilled) = WithdrawalQueue(queue).fill();

        assertEq(assetsFilled, 40);
        assertEq(sharesFilled, 20);
        assertEq(WithdrawalQueue(queue).totalFilled(), 20);
        assertEq(WithdrawalQueue(queue).pendingShares(), 80);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(queue), 40);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(vault), 1);
    }

    function test_FillDoesNothingWhenPreviewDepositOfWithdrawableRoundsToZero() public {
        uint256 shares = 100;
        uint256 managedAssets = 10_000;
        uint256 liquidAssets = 1;

        WithdrawalQueueFillToken(collateral).mint(vault, liquidAssets);
        WithdrawalQueueFillVault(vault).mintShares(alice, shares, managedAssets);

        vm.startPrank(alice);
        WithdrawalQueueFillVault(vault).approve(queue, shares);
        uint256 tokenId = WithdrawalQueue(queue).requestWithdraw(shares, alice);
        vm.stopPrank();

        (uint256 assetsFilled, uint256 sharesFilled) = WithdrawalQueue(queue).fill();

        assertEq(assetsFilled, 0);
        assertEq(sharesFilled, 0);
        assertEq(WithdrawalQueue(queue).totalFilled(), 0);
        assertEq(WithdrawalQueue(queue).pendingShares(), shares);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(queue), 0);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(vault), liquidAssets);

        (uint256 assetsClaimed, uint256 sharesClaimed) = WithdrawalQueue(queue).claimable(tokenId, type(uint256).max);

        assertEq(assetsClaimed, 0);
        assertEq(sharesClaimed, 0);
    }

    function test_FillUsesAllWithdrawableAssetsAtLowSharePrice() public {
        uint256 shares = 100;
        uint256 managedAssets = 50;
        uint256 liquidAssets = 40;

        WithdrawalQueueFillToken(collateral).mint(vault, liquidAssets);
        WithdrawalQueueFillVault(vault).mintShares(alice, shares, managedAssets);

        vm.startPrank(alice);
        WithdrawalQueueFillVault(vault).approve(queue, shares);
        uint256 tokenId = WithdrawalQueue(queue).requestWithdraw(shares, alice);
        vm.stopPrank();

        WithdrawalQueue(queue).fill();

        assertEq(WithdrawalQueue(queue).totalFilled(), 80);
        assertEq(WithdrawalQueue(queue).pendingShares(), 20);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(queue), liquidAssets);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(vault), 0);

        (uint256 assetsClaimed, uint256 sharesClaimed) = WithdrawalQueue(queue).claimable(tokenId, type(uint256).max);

        assertEq(assetsClaimed, liquidAssets);
        assertEq(sharesClaimed, 80);
    }

    function test_ClaimLimitedConsumesOneRequestAcrossPartialFillCheckpoints() public {
        uint256 shares = 100;

        WithdrawalQueueFillToken(collateral).mint(vault, 40);
        WithdrawalQueueFillVault(vault).mintShares(alice, shares, shares);

        vm.startPrank(alice);
        WithdrawalQueueFillVault(vault).approve(queue, shares);
        uint256 tokenId = WithdrawalQueue(queue).requestWithdraw(shares, alice);
        vm.stopPrank();

        WithdrawalQueue(queue).fill();

        assertEq(WithdrawalQueue(queue).totalFilled(), 40);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(queue), 40);

        WithdrawalQueueFillToken(collateral).mint(vault, 121);
        WithdrawalQueueFillVault(vault).setManagedAssets(121);

        WithdrawalQueue(queue).fill();

        assertEq(WithdrawalQueue(queue).totalFilled(), shares);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(queue), 161);

        (uint256 firstAssetsClaimed, uint256 firstSharesClaimed) = WithdrawalQueue(queue).claim(tokenId, 1);

        assertEq(firstAssetsClaimed, 40);
        assertEq(firstSharesClaimed, 40);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(alice), 40);

        (uint256 secondAssetsClaimed, uint256 secondSharesClaimed) = WithdrawalQueue(queue).claim(tokenId, 1);

        assertEq(secondAssetsClaimed, 120);
        assertEq(secondSharesClaimed, 60);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(alice), 160);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(queue), 1);
    }

    function test_ClaimableUsesFilledRequest() public {
        uint256 shares = 100;

        WithdrawalQueueFillToken(collateral).mint(vault, 100);
        WithdrawalQueueFillVault(vault).mintShares(alice, shares, 100);

        vm.startPrank(alice);
        WithdrawalQueueFillVault(vault).approve(queue, shares);
        WithdrawalQueue(queue).requestWithdraw(shares, alice);
        vm.stopPrank();

        WithdrawalQueue(queue).fill();

        (uint256 assetsClaimed, uint256 sharesClaimed) = WithdrawalQueue(queue).claimable(0, type(uint256).max);

        assertEq(assetsClaimed, 100);
        assertEq(sharesClaimed, shares);
    }

    function test_ClaimZeroIterationsIsNoOpAcrossFilledRequest() public {
        uint256 shares = 100;

        WithdrawalQueueFillToken(collateral).mint(vault, 100);
        WithdrawalQueueFillVault(vault).mintShares(alice, shares, 100);

        vm.startPrank(alice);
        WithdrawalQueueFillVault(vault).approve(queue, shares);
        uint256 tokenId = WithdrawalQueue(queue).requestWithdraw(shares, alice);
        vm.stopPrank();

        WithdrawalQueue(queue).fill();

        (uint256 assetsClaimed, uint256 sharesClaimed) = WithdrawalQueue(queue).claim(tokenId, 0);
        (, uint256 claimedShares,) = WithdrawalQueue(queue).requests(tokenId);

        assertEq(assetsClaimed, 0);
        assertEq(sharesClaimed, 0);
        assertEq(claimedShares, 0);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(alice), 0);

        (assetsClaimed, sharesClaimed) = WithdrawalQueue(queue).claim(tokenId, type(uint256).max);

        assertEq(assetsClaimed, 100);
        assertEq(sharesClaimed, shares);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(alice), 100);
    }

    function test_FillMarksSharesFilledEvenWhenRedeemRoundsToZero() public {
        WithdrawalQueueFillToken(collateral).mint(vault, 1);
        WithdrawalQueueFillVault(vault).mintShares(alice, 2, 1);

        vm.startPrank(alice);
        WithdrawalQueueFillVault(vault).approve(queue, 1);
        WithdrawalQueue(queue).requestWithdraw(1, alice);
        vm.stopPrank();

        WithdrawalQueue(queue).fill();

        assertEq(WithdrawalQueue(queue).totalFilled(), 1);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(queue), 0);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(vault), 1);

        (uint256 assetsClaimed, uint256 sharesClaimed) = WithdrawalQueue(queue).claimable(0, type(uint256).max);

        assertEq(assetsClaimed, 0);
        assertEq(sharesClaimed, 1);
    }

    function test_ClaimableUsesSharePriceCheckpointsAcrossFills() public {
        uint256 shares = 100;

        WithdrawalQueueFillToken(collateral).mint(vault, 100);
        WithdrawalQueueFillVault(vault).mintShares(alice, shares, 100);

        vm.startPrank(alice);
        WithdrawalQueueFillVault(vault).approve(queue, shares);
        uint256 firstTokenId = WithdrawalQueue(queue).requestWithdraw(shares, alice);
        vm.stopPrank();

        WithdrawalQueue(queue).fill();

        WithdrawalQueueFillToken(collateral).mint(vault, 50);
        WithdrawalQueueFillVault(vault).mintShares(alice, shares, 50);

        vm.startPrank(alice);
        WithdrawalQueueFillVault(vault).approve(queue, shares);
        uint256 secondTokenId = WithdrawalQueue(queue).requestWithdraw(shares, alice);
        vm.stopPrank();

        WithdrawalQueue(queue).fill();

        (uint256 firstAssetsClaimed, uint256 firstSharesClaimed) =
            WithdrawalQueue(queue).claimable(firstTokenId, type(uint256).max);
        (uint256 secondAssetsClaimed, uint256 secondSharesClaimed) =
            WithdrawalQueue(queue).claimable(secondTokenId, type(uint256).max);

        assertEq(firstAssetsClaimed, 100);
        assertEq(firstSharesClaimed, shares);
        assertEq(secondAssetsClaimed, 50);
        assertEq(secondSharesClaimed, shares);
    }

    function test_FillSkipsUpwardSharePriceDriftBelowOneTenthMicroToken() public {
        uint256 shares = 1 ether;
        uint256 assets = 1 ether;
        uint256 drift = 1e11 - 1;

        WithdrawalQueueFillToken(collateral).mint(vault, assets + drift);
        WithdrawalQueueFillVault(vault).mintShares(alice, shares, assets + drift);

        vm.startPrank(alice);
        WithdrawalQueueFillVault(vault).approve(queue, shares);
        uint256 tokenId = WithdrawalQueue(queue).requestWithdraw(shares, alice);
        vm.stopPrank();

        WithdrawalQueue(queue).fill();

        (uint256 assetsClaimed, uint256 sharesClaimed) = WithdrawalQueue(queue).claimable(tokenId, type(uint256).max);

        assertEq(assetsClaimed, assets);
        assertEq(sharesClaimed, shares);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(queue), assets + drift);

        WithdrawalQueue(queue).claim(tokenId, type(uint256).max);

        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(alice), assets);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(queue), drift);

        (uint256 secondAssetsClaimed, uint256 secondSharesClaimed) =
            WithdrawalQueue(queue).claim(tokenId, type(uint256).max);

        assertEq(secondAssetsClaimed, 0);
        assertEq(secondSharesClaimed, 0);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(alice), assets);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(queue), drift);
    }

    function test_FillCheckpointsOneAtomUpwardDriftWithSixDecimalSharePriceTolerance() public {
        uint256 virtualShares = 1e12;
        uint256 deadShares = 1e18;
        uint256 seedAssets = 1e6;
        uint256 shares = 1e18;
        uint256 assets = 1e6;
        uint256 drift = 3;

        WithdrawalQueueFillToken(collateral).setDecimals(6);
        WithdrawalQueueFillVault(vault).setShareConfig(18, virtualShares);
        queue = address(new WithdrawalQueue());
        vm.prank(vault);
        WithdrawalQueue(queue).initialize();

        WithdrawalQueueFillToken(collateral).mint(vault, seedAssets + assets + drift);
        WithdrawalQueueFillVault(vault).mintShares(address(0xDEAD), deadShares, seedAssets);
        WithdrawalQueueFillVault(vault).mintShares(alice, shares, assets);
        WithdrawalQueueFillVault(vault).setManagedAssets(seedAssets + assets + drift);

        vm.startPrank(alice);
        WithdrawalQueueFillVault(vault).approve(queue, shares);
        uint256 tokenId = WithdrawalQueue(queue).requestWithdraw(shares, alice);
        vm.stopPrank();

        WithdrawalQueue(queue).fill();

        (uint256 assetsClaimed, uint256 sharesClaimed) = WithdrawalQueue(queue).claimable(tokenId, type(uint256).max);

        assertEq(assetsClaimed, assets + 1);
        assertEq(sharesClaimed, shares);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(queue), assets + 1);
    }

    function test_FillCheckpointsSmallDownwardSharePriceDrift() public {
        uint256 shares = 20_000;

        WithdrawalQueueFillToken(collateral).mint(vault, 19_999);
        WithdrawalQueueFillVault(vault).mintShares(alice, shares, 19_999);

        vm.startPrank(alice);
        WithdrawalQueueFillVault(vault).approve(queue, shares);
        uint256 tokenId = WithdrawalQueue(queue).requestWithdraw(shares, alice);
        vm.stopPrank();

        WithdrawalQueue(queue).fill();

        (uint256 assetsClaimed, uint256 sharesClaimed) = WithdrawalQueue(queue).claimable(tokenId, type(uint256).max);

        assertEq(assetsClaimed, 19_999);
        assertEq(sharesClaimed, shares);
    }

    function test_FillCheckpointsTinyDownwardSharePriceDriftToAvoidOverpay() public {
        uint256 shares = 1 ether;
        uint256 assets = 1 ether;
        uint256 drift = 1e11 - 1;

        WithdrawalQueueFillToken(collateral).mint(vault, assets - drift);
        WithdrawalQueueFillVault(vault).mintShares(alice, shares, assets - drift);

        vm.startPrank(alice);
        WithdrawalQueueFillVault(vault).approve(queue, shares);
        uint256 tokenId = WithdrawalQueue(queue).requestWithdraw(shares, alice);
        vm.stopPrank();

        WithdrawalQueue(queue).fill();

        (uint256 assetsClaimed, uint256 sharesClaimed) = WithdrawalQueue(queue).claimable(tokenId, type(uint256).max);

        assertEq(assetsClaimed, assets - drift);
        assertEq(sharesClaimed, shares);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(queue), assets - drift);

        WithdrawalQueue(queue).claim(tokenId, type(uint256).max);

        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(alice), assets - drift);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(queue), 0);
    }

    function test_FillCheckpointsDownwardDriftAfterSkippedUpwardDrift() public {
        address bob = address(0xB0B);
        uint256 shares = 1 ether;
        uint256 assets = 1 ether;
        uint256 drift = 1e11 - 1;

        WithdrawalQueueFillToken(collateral).mint(vault, assets + drift);
        WithdrawalQueueFillVault(vault).mintShares(alice, shares, assets + drift);

        vm.startPrank(alice);
        WithdrawalQueueFillVault(vault).approve(queue, shares);
        uint256 firstTokenId = WithdrawalQueue(queue).requestWithdraw(shares, alice);
        vm.stopPrank();

        WithdrawalQueue(queue).fill();
        WithdrawalQueue(queue).claim(firstTokenId, type(uint256).max);

        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(alice), assets);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(queue), drift);

        WithdrawalQueueFillToken(collateral).mint(vault, assets - drift);
        WithdrawalQueueFillVault(vault).mintShares(bob, shares, assets - drift);

        vm.startPrank(bob);
        WithdrawalQueueFillVault(vault).approve(queue, shares);
        uint256 secondTokenId = WithdrawalQueue(queue).requestWithdraw(shares, bob);
        vm.stopPrank();

        WithdrawalQueue(queue).fill();

        (uint256 assetsClaimed, uint256 sharesClaimed) =
            WithdrawalQueue(queue).claimable(secondTokenId, type(uint256).max);

        assertEq(assetsClaimed, assets - drift);
        assertEq(sharesClaimed, shares);

        WithdrawalQueue(queue).claim(secondTokenId, type(uint256).max);

        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(bob), assets - drift);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(queue), drift);
    }

    function test_ClaimPaysCurrentNftOwner() public {
        address bob = address(0xB0B);
        uint256 shares = 100;

        WithdrawalQueueFillToken(collateral).mint(vault, 100);
        WithdrawalQueueFillVault(vault).mintShares(alice, shares, 100);

        vm.startPrank(alice);
        WithdrawalQueueFillVault(vault).approve(queue, shares);
        uint256 tokenId = WithdrawalQueue(queue).requestWithdraw(shares, alice);
        WithdrawalQueue(queue).transferFrom(alice, bob, tokenId);
        vm.stopPrank();

        WithdrawalQueue(queue).fill();
        WithdrawalQueue(queue).claim(tokenId, type(uint256).max);

        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(bob), 100);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(alice), 0);
    }
}
