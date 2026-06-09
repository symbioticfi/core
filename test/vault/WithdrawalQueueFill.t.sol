// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";

import {WithdrawalQueue} from "../../src/contracts/vault/WithdrawalQueue.sol";
import {WithdrawalQueueFactory} from "../../src/contracts/WithdrawalQueueFactory.sol";
import {IWithdrawalQueue} from "../../src/interfaces/vault/IWithdrawalQueue.sol";

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

    function mint(address account, uint256 assets) external {
        _mint(account, assets);
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

    function onDeposit() external {}

    function sweepPending() external returns (uint256) {
        ++syncCalls;
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

    function accrueInterest() external returns (uint256 managementFeeShares, uint256 performanceFeeShares) {
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

        queue = _deployQueue();
    }

    function test_WithdrawalQueueExposesRequestRedeemApi() public pure {
        assertEq(IWithdrawalQueue.requestRedeem.selector, bytes4(keccak256("requestRedeem(uint256,address)")));
        assertEq(IWithdrawalQueue.isClaimed.selector, bytes4(keccak256("isClaimed(uint256)")));
        assertEq(IWithdrawalQueue.totalRequests.selector, bytes4(keccak256("totalRequests()")));
    }

    function test_RequestRedeemRevertsZeroShares() public {
        vm.expectRevert(IWithdrawalQueue.ZeroShares.selector);
        WithdrawalQueue(queue).requestRedeem(0, alice);
    }

    function test_RequestRedeemUsesTotalRequestsAsTokenId() public {
        address bob = address(0xB0B);

        WithdrawalQueueFillVault(vault).mintShares(alice, 60, 60);

        assertEq(WithdrawalQueue(queue).totalRequests(), 0);

        vm.startPrank(alice);
        WithdrawalQueueFillVault(vault).approve(queue, 60);
        uint256 firstTokenId = WithdrawalQueue(queue).requestRedeem(40, alice);
        uint256 secondTokenId = WithdrawalQueue(queue).requestRedeem(20, bob);
        vm.stopPrank();

        assertEq(firstTokenId, 0);
        assertEq(secondTokenId, 1);
        assertEq(WithdrawalQueue(queue).totalRequests(), 2);
        assertEq(WithdrawalQueue(queue).ownerOf(firstTokenId), alice);
        assertEq(WithdrawalQueue(queue).ownerOf(secondTokenId), bob);
    }

    function test_RequestStorageUsesMappingAndExplicitTotalRequestsCounter() public {
        WithdrawalQueueFillVault(vault).mintShares(alice, 40, 40);

        vm.startPrank(alice);
        WithdrawalQueueFillVault(vault).approve(queue, 40);
        WithdrawalQueue(queue).requestRedeem(40, alice);
        vm.stopPrank();

        assertEq(uint256(vm.load(queue, bytes32(uint256(12)))), 0);
        assertEq(uint256(vm.load(queue, bytes32(uint256(13)))), 1);
        assertEq(WithdrawalQueue(queue).totalRequests(), 1);
    }

    function test_MulticallCanRequestRedeemAndBubbleReverts() public {
        WithdrawalQueueFillVault(vault).mintShares(alice, 100, 100);

        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeCall(IWithdrawalQueue.requestRedeem, (40, alice));

        vm.startPrank(alice);
        WithdrawalQueueFillVault(vault).approve(queue, 40);
        WithdrawalQueue(queue).multicall(calls);
        vm.stopPrank();

        assertEq(WithdrawalQueue(queue).totalRequested(), 40);
        assertEq(WithdrawalQueue(queue).ownerOf(0), alice);

        calls[0] = abi.encodeCall(IWithdrawalQueue.requestRedeem, (0, alice));

        vm.expectRevert(IWithdrawalQueue.ZeroShares.selector);
        WithdrawalQueue(queue).multicall(calls);
    }

    function test_RequestRedeemNotifiesDelegatorAndFillRedeemsPendingShares() public {
        WithdrawalQueueFillToken(collateral).mint(vault, 100);
        WithdrawalQueueFillVault(vault).mintShares(alice, 100, 100);

        vm.startPrank(alice);
        WithdrawalQueueFillVault(vault).approve(queue, 100);
        vm.expectEmit(true, true, true, true, queue);
        emit IWithdrawalQueue.RequestRedeem(alice, alice, 100, 0);
        WithdrawalQueue(queue).requestRedeem(100, alice);
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
        WithdrawalQueue(queue).requestRedeem(shares, alice);
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
        WithdrawalQueue(queue).requestRedeem(shares, alice);
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
        uint256 tokenId = WithdrawalQueue(queue).requestRedeem(shares, alice);
        vm.stopPrank();

        WithdrawalQueue(queue).fill();

        assertEq(WithdrawalQueue(queue).totalFilled(), liquidAssets);
        assertEq(WithdrawalQueue(queue).pendingShares(), shares - liquidAssets);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(queue), liquidAssets);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(vault), 0);

        (uint256 assetsClaimed, uint256 sharesClaimed) = WithdrawalQueue(queue).claimable(tokenId);

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
        uint256 tokenId = WithdrawalQueue(queue).requestRedeem(shares, alice);
        vm.stopPrank();

        WithdrawalQueue(queue).fill();

        assertEq(WithdrawalQueue(queue).totalFilled(), 20);
        assertEq(WithdrawalQueue(queue).pendingShares(), 80);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(queue), liquidAssets);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(vault), 0);

        (uint256 assetsClaimed, uint256 sharesClaimed) = WithdrawalQueue(queue).claimable(tokenId);

        assertEq(assetsClaimed, liquidAssets);
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
        WithdrawalQueue(queue).requestRedeem(shares, alice);
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
        uint256 tokenId = WithdrawalQueue(queue).requestRedeem(shares, alice);
        vm.stopPrank();

        (uint256 assetsFilled, uint256 sharesFilled) = WithdrawalQueue(queue).fill();

        assertEq(assetsFilled, 0);
        assertEq(sharesFilled, 0);
        assertEq(WithdrawalQueue(queue).totalFilled(), 0);
        assertEq(WithdrawalQueue(queue).pendingShares(), shares);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(queue), 0);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(vault), liquidAssets);

        (uint256 assetsClaimed, uint256 sharesClaimed) = WithdrawalQueue(queue).claimable(tokenId);

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
        uint256 tokenId = WithdrawalQueue(queue).requestRedeem(shares, alice);
        vm.stopPrank();

        WithdrawalQueue(queue).fill();

        assertEq(WithdrawalQueue(queue).totalFilled(), 80);
        assertEq(WithdrawalQueue(queue).pendingShares(), 20);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(queue), liquidAssets);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(vault), 0);

        (uint256 assetsClaimed, uint256 sharesClaimed) = WithdrawalQueue(queue).claimable(tokenId);

        assertEq(assetsClaimed, liquidAssets);
        assertEq(sharesClaimed, 80);
    }

    function test_ClaimAcrossPartialFills() public {
        uint256 shares = 100;

        WithdrawalQueueFillToken(collateral).mint(vault, 40);
        WithdrawalQueueFillVault(vault).mintShares(alice, shares, shares);

        vm.startPrank(alice);
        WithdrawalQueueFillVault(vault).approve(queue, shares);
        uint256 tokenId = WithdrawalQueue(queue).requestRedeem(shares, alice);
        vm.stopPrank();

        WithdrawalQueue(queue).fill();

        assertEq(WithdrawalQueue(queue).totalFilled(), 40);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(queue), 40);

        WithdrawalQueueFillToken(collateral).mint(vault, 121);
        WithdrawalQueueFillVault(vault).setManagedAssets(121);

        WithdrawalQueue(queue).fill();

        assertEq(WithdrawalQueue(queue).totalFilled(), shares);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(queue), 161);

        (uint256 firstAssetsClaimed, uint256 firstSharesClaimed) = WithdrawalQueue(queue).claim(tokenId);

        assertEq(firstAssetsClaimed, 161);
        assertEq(firstSharesClaimed, shares);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(alice), 161);

        (uint256 secondAssetsClaimed, uint256 secondSharesClaimed) = WithdrawalQueue(queue).claim(tokenId);

        assertEq(secondAssetsClaimed, 0);
        assertEq(secondSharesClaimed, 0);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(alice), 161);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(queue), 0);
    }

    function test_IsClaimedTracksPartialAndFullClaims() public {
        uint256 shares = 100;

        WithdrawalQueueFillToken(collateral).mint(vault, 40);
        WithdrawalQueueFillVault(vault).mintShares(alice, shares, shares);

        vm.startPrank(alice);
        WithdrawalQueueFillVault(vault).approve(queue, shares);
        uint256 tokenId = WithdrawalQueue(queue).requestRedeem(shares, alice);
        vm.stopPrank();

        assertEq(IWithdrawalQueue(queue).isClaimed(tokenId), false);

        WithdrawalQueue(queue).fill();
        WithdrawalQueue(queue).claim(tokenId);

        assertEq(IWithdrawalQueue(queue).isClaimed(tokenId), false);

        WithdrawalQueueFillToken(collateral).mint(vault, 60);
        WithdrawalQueue(queue).fill();
        WithdrawalQueue(queue).claim(tokenId);

        assertEq(IWithdrawalQueue(queue).isClaimed(tokenId), true);
    }

    function test_ClaimAcrossManyTinyFills() public {
        uint256 shares = 32;

        WithdrawalQueueFillVault(vault).mintShares(alice, shares, shares);

        vm.startPrank(alice);
        WithdrawalQueueFillVault(vault).approve(queue, shares);
        uint256 tokenId = WithdrawalQueue(queue).requestRedeem(shares, alice);
        vm.stopPrank();

        for (uint256 i; i < shares; ++i) {
            WithdrawalQueueFillToken(collateral).mint(vault, 1);
            WithdrawalQueue(queue).fill();
        }

        (uint256 assetsClaimed, uint256 sharesClaimed) = WithdrawalQueue(queue).claim(tokenId);

        assertEq(assetsClaimed, shares);
        assertEq(sharesClaimed, shares);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(alice), shares);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(queue), 0);
    }

    function test_ClaimableUsesFilledRequest() public {
        uint256 shares = 100;

        WithdrawalQueueFillToken(collateral).mint(vault, 100);
        WithdrawalQueueFillVault(vault).mintShares(alice, shares, 100);

        vm.startPrank(alice);
        WithdrawalQueueFillVault(vault).approve(queue, shares);
        WithdrawalQueue(queue).requestRedeem(shares, alice);
        vm.stopPrank();

        WithdrawalQueue(queue).fill();

        (uint256 assetsClaimed, uint256 sharesClaimed) = WithdrawalQueue(queue).claimable(0);

        assertEq(assetsClaimed, 100);
        assertEq(sharesClaimed, shares);
    }

    function test_ClaimAcrossFilledRequest() public {
        uint256 shares = 100;

        WithdrawalQueueFillToken(collateral).mint(vault, 100);
        WithdrawalQueueFillVault(vault).mintShares(alice, shares, 100);

        vm.startPrank(alice);
        WithdrawalQueueFillVault(vault).approve(queue, shares);
        uint256 tokenId = WithdrawalQueue(queue).requestRedeem(shares, alice);
        vm.stopPrank();

        WithdrawalQueue(queue).fill();

        (uint256 assetsClaimed, uint256 sharesClaimed) = WithdrawalQueue(queue).claim(tokenId);
        (, uint256 claimedShares,) = WithdrawalQueue(queue).requests(tokenId);

        assertEq(assetsClaimed, 100);
        assertEq(sharesClaimed, shares);
        assertEq(claimedShares, shares);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(alice), 100);
    }

    function test_FillMarksSharesFilledEvenWhenRedeemRoundsToZero() public {
        WithdrawalQueueFillToken(collateral).mint(vault, 1);
        WithdrawalQueueFillVault(vault).mintShares(alice, 2, 1);

        vm.startPrank(alice);
        WithdrawalQueueFillVault(vault).approve(queue, 1);
        WithdrawalQueue(queue).requestRedeem(1, alice);
        vm.stopPrank();

        WithdrawalQueue(queue).fill();

        assertEq(WithdrawalQueue(queue).totalFilled(), 1);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(queue), 0);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(vault), 1);

        (uint256 assetsClaimed, uint256 sharesClaimed) = WithdrawalQueue(queue).claimable(0);

        assertEq(assetsClaimed, 0);
        assertEq(sharesClaimed, 1);
    }

    function test_ClaimableUsesCumulativeFillCurveAcrossFills() public {
        uint256 shares = 100;

        WithdrawalQueueFillToken(collateral).mint(vault, 100);
        WithdrawalQueueFillVault(vault).mintShares(alice, shares, 100);

        vm.startPrank(alice);
        WithdrawalQueueFillVault(vault).approve(queue, shares);
        uint256 firstTokenId = WithdrawalQueue(queue).requestRedeem(shares, alice);
        vm.stopPrank();

        WithdrawalQueue(queue).fill();

        WithdrawalQueueFillToken(collateral).mint(vault, 50);
        WithdrawalQueueFillVault(vault).mintShares(alice, shares, 50);

        vm.startPrank(alice);
        WithdrawalQueueFillVault(vault).approve(queue, shares);
        uint256 secondTokenId = WithdrawalQueue(queue).requestRedeem(shares, alice);
        vm.stopPrank();

        WithdrawalQueue(queue).fill();

        (uint256 firstAssetsClaimed, uint256 firstSharesClaimed) = WithdrawalQueue(queue).claimable(firstTokenId);
        (uint256 secondAssetsClaimed, uint256 secondSharesClaimed) = WithdrawalQueue(queue).claimable(secondTokenId);

        assertEq(firstAssetsClaimed, 100);
        assertEq(firstSharesClaimed, shares);
        assertEq(secondAssetsClaimed, 50);
        assertEq(secondSharesClaimed, shares);
    }

    function test_ClaimReceivesExactAssetsFromBelowOldToleranceUpwardDrift() public {
        uint256 shares = 1 ether;
        uint256 assets = 1 ether;
        uint256 drift = 1e11 - 1;

        WithdrawalQueueFillToken(collateral).mint(vault, assets + drift);
        WithdrawalQueueFillVault(vault).mintShares(alice, shares, assets + drift);

        vm.startPrank(alice);
        WithdrawalQueueFillVault(vault).approve(queue, shares);
        uint256 tokenId = WithdrawalQueue(queue).requestRedeem(shares, alice);
        vm.stopPrank();

        WithdrawalQueue(queue).fill();

        (uint256 assetsClaimed, uint256 sharesClaimed) = WithdrawalQueue(queue).claimable(tokenId);

        assertEq(assetsClaimed, assets + drift);
        assertEq(sharesClaimed, shares);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(queue), assets + drift);

        WithdrawalQueue(queue).claim(tokenId);

        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(alice), assets + drift);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(queue), 0);

        (uint256 secondAssetsClaimed, uint256 secondSharesClaimed) = WithdrawalQueue(queue).claim(tokenId);

        assertEq(secondAssetsClaimed, 0);
        assertEq(secondSharesClaimed, 0);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(alice), assets + drift);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(queue), 0);
    }

    function test_ClaimReceivesExactSixDecimalAssetsAfterUpwardDrift() public {
        uint256 virtualShares = 1e12;
        uint256 seedShares = 1e18;
        uint256 seedAssets = 1e6;
        uint256 shares = 1e18;
        uint256 assets = 1e6;
        uint256 drift = 3;

        WithdrawalQueueFillToken(collateral).setDecimals(6);
        WithdrawalQueueFillVault(vault).setShareConfig(18, virtualShares);
        queue = _deployQueue();

        WithdrawalQueueFillToken(collateral).mint(vault, seedAssets + assets + drift);
        WithdrawalQueueFillVault(vault).mintShares(address(0xBEEF), seedShares, seedAssets);
        WithdrawalQueueFillVault(vault).mintShares(alice, shares, assets);
        WithdrawalQueueFillVault(vault).setManagedAssets(seedAssets + assets + drift);

        vm.startPrank(alice);
        WithdrawalQueueFillVault(vault).approve(queue, shares);
        uint256 tokenId = WithdrawalQueue(queue).requestRedeem(shares, alice);
        vm.stopPrank();

        WithdrawalQueue(queue).fill();

        (uint256 assetsClaimed, uint256 sharesClaimed) = WithdrawalQueue(queue).claimable(tokenId);

        assertEq(assetsClaimed, assets + 1);
        assertEq(sharesClaimed, shares);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(queue), assets + 1);
    }

    function test_ClaimReceivesExactAssetsAfterSmallDownwardDrift() public {
        uint256 shares = 20_000;

        WithdrawalQueueFillToken(collateral).mint(vault, 19_999);
        WithdrawalQueueFillVault(vault).mintShares(alice, shares, 19_999);

        vm.startPrank(alice);
        WithdrawalQueueFillVault(vault).approve(queue, shares);
        uint256 tokenId = WithdrawalQueue(queue).requestRedeem(shares, alice);
        vm.stopPrank();

        WithdrawalQueue(queue).fill();

        (uint256 assetsClaimed, uint256 sharesClaimed) = WithdrawalQueue(queue).claimable(tokenId);

        assertEq(assetsClaimed, 19_999);
        assertEq(sharesClaimed, shares);
    }

    function test_ClaimReceivesExactAssetsAfterTinyDownwardDrift() public {
        uint256 shares = 1 ether;
        uint256 assets = 1 ether;
        uint256 drift = 1e11 - 1;

        WithdrawalQueueFillToken(collateral).mint(vault, assets - drift);
        WithdrawalQueueFillVault(vault).mintShares(alice, shares, assets - drift);

        vm.startPrank(alice);
        WithdrawalQueueFillVault(vault).approve(queue, shares);
        uint256 tokenId = WithdrawalQueue(queue).requestRedeem(shares, alice);
        vm.stopPrank();

        WithdrawalQueue(queue).fill();

        (uint256 assetsClaimed, uint256 sharesClaimed) = WithdrawalQueue(queue).claimable(tokenId);

        assertEq(assetsClaimed, assets - drift);
        assertEq(sharesClaimed, shares);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(queue), assets - drift);

        WithdrawalQueue(queue).claim(tokenId);

        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(alice), assets - drift);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(queue), 0);
    }

    function test_ClaimReceivesExactAssetsAcrossUpwardAndDownwardDrift() public {
        address bob = address(0xB0B);
        uint256 shares = 1 ether;
        uint256 assets = 1 ether;
        uint256 drift = 1e11 - 1;

        WithdrawalQueueFillToken(collateral).mint(vault, assets + drift);
        WithdrawalQueueFillVault(vault).mintShares(alice, shares, assets + drift);

        vm.startPrank(alice);
        WithdrawalQueueFillVault(vault).approve(queue, shares);
        uint256 firstTokenId = WithdrawalQueue(queue).requestRedeem(shares, alice);
        vm.stopPrank();

        WithdrawalQueue(queue).fill();
        WithdrawalQueue(queue).claim(firstTokenId);

        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(alice), assets + drift);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(queue), 0);

        WithdrawalQueueFillToken(collateral).mint(vault, assets - drift);
        WithdrawalQueueFillVault(vault).mintShares(bob, shares, assets - drift);

        vm.startPrank(bob);
        WithdrawalQueueFillVault(vault).approve(queue, shares);
        uint256 secondTokenId = WithdrawalQueue(queue).requestRedeem(shares, bob);
        vm.stopPrank();

        WithdrawalQueue(queue).fill();

        (uint256 assetsClaimed, uint256 sharesClaimed) = WithdrawalQueue(queue).claimable(secondTokenId);

        assertEq(assetsClaimed, assets - drift);
        assertEq(sharesClaimed, shares);

        WithdrawalQueue(queue).claim(secondTokenId);

        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(bob), assets - drift);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(queue), 0);
    }

    function test_ClaimPaysCurrentNftOwner() public {
        address bob = address(0xB0B);
        uint256 shares = 100;

        WithdrawalQueueFillToken(collateral).mint(vault, 100);
        WithdrawalQueueFillVault(vault).mintShares(alice, shares, 100);

        vm.startPrank(alice);
        WithdrawalQueueFillVault(vault).approve(queue, shares);
        uint256 tokenId = WithdrawalQueue(queue).requestRedeem(shares, alice);
        WithdrawalQueue(queue).transferFrom(alice, bob, tokenId);
        vm.stopPrank();

        WithdrawalQueue(queue).fill();
        WithdrawalQueue(queue).claim(tokenId);

        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(bob), 100);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(alice), 0);
    }

    function _deployQueue() internal returns (address queue_) {
        WithdrawalQueueFactory factory = new WithdrawalQueueFactory(address(this));
        factory.whitelist(address(new WithdrawalQueue(address(factory))));
        queue_ = factory.create(
            1, vault, abi.encode(WithdrawalQueueFillVault(vault).name(), WithdrawalQueueFillVault(vault).symbol())
        );
    }
}
