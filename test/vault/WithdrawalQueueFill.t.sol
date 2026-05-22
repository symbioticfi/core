// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";

import {WithdrawalQueue} from "../../src/contracts/vault/WithdrawalQueue.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract WithdrawalQueueFillToken is ERC20 {
    constructor() ERC20("Token", "TKN") {}

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

    constructor(address collateral_) ERC20("Vault Share", "vTKN") {
        collateral = collateral_;
    }

    function setDelegator(address delegator_) external {
        delegatorContract = delegator_;
    }

    function mintShares(address account, uint256 shares, uint256 assets) external {
        _mint(account, shares);
        managedAssets += assets;
    }

    function setManagedAssets(uint256 assets) external {
        managedAssets = assets;
    }

    function asset() external view returns (address) {
        return collateral;
    }

    function delegator() external view returns (address) {
        return delegatorContract;
    }

    function totalAssets() external view returns (uint256) {
        return managedAssets;
    }

    function accrueInterest() external pure returns (uint256 performanceFeeShares, uint256 managementFeeShares) {}

    function previewRedeem(uint256 shares) external view returns (uint256) {
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

    function test_RequestWithdrawNotifiesDelegatorAndFillOnlyUsesLiquidVaultAssets() public {
        WithdrawalQueueFillToken(collateral).mint(vault, 30);
        WithdrawalQueueFillVault(vault).mintShares(alice, 100, 100);
        WithdrawalQueueFillDelegator(delegator).setTotalAssets(70);

        vm.startPrank(alice);
        WithdrawalQueueFillVault(vault).approve(queue, 100);
        WithdrawalQueue(queue).requestWithdraw(100, alice);
        vm.stopPrank();

        WithdrawalQueue(queue).fill();

        assertEq(WithdrawalQueueFillDelegator(delegator).syncCalls(), 1);
        assertEq(WithdrawalQueue(queue).totalFilled(), 30);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(queue), 30);
    }

    function test_ClaimableUsesFilledPortionOfRequest() public {
        uint256 shares = 100 * 1e6;

        WithdrawalQueueFillToken(collateral).mint(vault, 30);
        WithdrawalQueueFillVault(vault).mintShares(alice, shares, 100);
        WithdrawalQueueFillDelegator(delegator).setTotalAssets(70);

        vm.startPrank(alice);
        WithdrawalQueueFillVault(vault).approve(queue, shares);
        WithdrawalQueue(queue).requestWithdraw(shares, alice);
        vm.stopPrank();

        WithdrawalQueue(queue).fill();

        (uint256 assetsClaimed, uint256 sharesClaimed) = WithdrawalQueue(queue).claimable(0);

        assertEq(assetsClaimed, 30);
        assertEq(sharesClaimed, 30 * 1e6);
    }

    function test_FillSkipsDustLiquidityBelowOneRedeemableShare() public {
        WithdrawalQueueFillToken(collateral).mint(vault, 1);
        WithdrawalQueueFillVault(vault).mintShares(alice, 2, 4);

        vm.startPrank(alice);
        WithdrawalQueueFillVault(vault).approve(queue, 1);
        WithdrawalQueue(queue).requestWithdraw(1, alice);
        vm.stopPrank();

        WithdrawalQueue(queue).fill();

        assertEq(WithdrawalQueue(queue).totalFilled(), 0);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(queue), 0);
        assertEq(WithdrawalQueueFillToken(collateral).balanceOf(vault), 1);
    }

    function test_ClaimableSplitsRequestAcrossSharePriceCheckpoints() public {
        uint256 shares = 200 * 1e6;

        WithdrawalQueueFillToken(collateral).mint(vault, 100);
        WithdrawalQueueFillVault(vault).mintShares(alice, shares, 200);
        WithdrawalQueueFillDelegator(delegator).setTotalAssets(100);

        vm.startPrank(alice);
        WithdrawalQueueFillVault(vault).approve(queue, shares);
        WithdrawalQueue(queue).requestWithdraw(shares, alice);
        vm.stopPrank();

        WithdrawalQueue(queue).fill();
        assertEq(WithdrawalQueue(queue).totalFilled(), 100 * 1e6);

        WithdrawalQueueFillVault(vault).setManagedAssets(50);
        WithdrawalQueueFillToken(collateral).mint(vault, 50);

        WithdrawalQueue(queue).fill();

        (uint256 assetsClaimed, uint256 sharesClaimed) = WithdrawalQueue(queue).claimable(0);

        assertEq(assetsClaimed, 150);
        assertEq(sharesClaimed, shares);
    }

    function test_ClaimPaysCurrentNftOwner() public {
        address bob = address(0xB0B);
        uint256 shares = 100 * 1e6;

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
