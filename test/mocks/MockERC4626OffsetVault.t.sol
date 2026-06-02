// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";

import {MockERC4626OffsetVault} from "./MockERC4626OffsetVault.sol";
import {Token} from "./Token.sol";

contract MockERC4626OffsetVaultTest is Test {
    Token internal asset;
    MockERC4626OffsetVault internal vault;

    function setUp() public {
        asset = new Token("Asset");
        vault = new MockERC4626OffsetVault(asset);

        asset.approve(address(vault), type(uint256).max);
    }

    function test_UsesAssetAdjustedDecimalOffsetAndAllowsTotalAssetsChanges() public {
        vault.deposit(1000 ether, address(this));

        assertEq(vault.decimalsOffset(), 0);
        assertEq(vault.decimals(), 18);
        assertEq(vault.totalAssets(), 1000 ether);

        vault.increaseTotalAssets(100 ether);
        assertEq(vault.totalAssets(), 1100 ether);

        vault.decreaseTotalAssets(40 ether, address(this));
        assertEq(vault.totalAssets(), 1060 ether);
    }

    function test_SimulatesHundredXMaximumSharePriceAfterSupplyChanges() public {
        vault.deposit(1000 ether, address(this));
        uint256 initialSharePrice = _sharePrice();

        uint256 supplyBeforeIncrease = vault.totalSupply();
        vault.deposit(500 ether, address(this));
        assertGt(vault.totalSupply(), supplyBeforeIncrease);

        uint256 supplyBeforeDecrease = vault.totalSupply();
        vault.withdraw(200 ether, address(this), address(this));
        assertLt(vault.totalSupply(), supplyBeforeDecrease);

        uint256 maxSharePrice = initialSharePrice * 100;
        uint256 maxTotalAssets = _maxTotalAssetsForSharePrice(maxSharePrice);
        vault.increaseTotalAssets(maxTotalAssets - vault.totalAssets());

        assertApproxEqAbs(_sharePrice(), maxSharePrice, 1);

        vault.decreaseTotalAssets(1 ether, address(this));
        assertLt(_sharePrice(), maxSharePrice);
    }

    function test_SimulatesVirtualSharePriceChangeAfterNearFullWithdraw() public {
        vault.deposit(1000 ether, address(this));
        uint256 initialVirtualSharePrice = _sharePrice();

        vault.deposit(500 ether, address(this));
        vault.withdraw(200 ether, address(this), address(this));

        uint256 maxVirtualSharePrice = initialVirtualSharePrice * 100;
        uint256 maxTotalAssets = _maxTotalAssetsForSharePrice(maxVirtualSharePrice);
        vault.increaseTotalAssets(maxTotalAssets - vault.totalAssets());

        assertEq(_sharePrice(), maxVirtualSharePrice);
        assertEq(_rawSharePrice(), maxVirtualSharePrice);

        vault.withdraw(vault.maxWithdraw(address(this)) - 1, address(this), address(this));

        assertEq(vault.totalAssets(), 100);
        assertEq(vault.totalSupply(), 0);
        assertEq(_sharePrice(), maxVirtualSharePrice + 1 ether);
    }

    function test_SimulatesConvertToAssetsPriceDeltaAfterDepositAndWithdraw() public {
        uint256 virtualShares = 10 ** vault.decimalsOffset();
        uint256 initialSharePrice = _sharePrice();
        uint256 maxSharePrice = initialSharePrice * 100;
        uint256 maxAllowedDelta = maxSharePrice / virtualShares;
        uint256 maxPossibleDelta = maxSharePrice - maxSharePrice * virtualShares / (virtualShares + 1);

        assertEq(initialSharePrice, 1 ether);

        vault.deposit(100 ether, address(this));

        uint256 depositPriceBefore = _sharePrice();
        vault.deposit(1 ether, address(this));
        uint256 depositDelta = _sharePrice() - depositPriceBefore;

        assertEq(depositDelta, 0);
        assertLt(depositDelta, maxAllowedDelta);

        vault = new MockERC4626OffsetVault(asset);
        asset.approve(address(vault), type(uint256).max);

        uint256 k = 1e20;
        uint256 denominatorBefore = (virtualShares + 1) * k - 1;
        uint256 assetsBefore = 100 * k - 1;
        uint256 sharesBefore = denominatorBefore - virtualShares;

        vault.mint(sharesBefore, address(this));
        vault.increaseTotalAssets(assetsBefore - vault.totalAssets());

        uint256 withdrawPriceBefore = _sharePrice();
        vault.withdraw(assetsBefore - 99, address(this), address(this));
        uint256 withdrawDelta = _sharePrice() - withdrawPriceBefore;

        assertEq(vault.totalAssets(), 99);
        assertEq(vault.totalSupply(), 0);
        assertEq(_sharePrice(), maxSharePrice);
        assertEq(withdrawDelta, maxPossibleDelta);
        assertEq(withdrawDelta, 50 ether);
        assertLt(withdrawDelta, maxAllowedDelta);
        assertGt(withdrawDelta, depositDelta);
    }

    function _sharePrice() internal view returns (uint256) {
        return vault.convertToAssets(10 ** vault.decimals());
    }

    function _rawSharePrice() internal view returns (uint256) {
        return vault.totalAssets() * 10 ** vault.decimals() / vault.totalSupply();
    }

    function _maxTotalAssetsForSharePrice(uint256 sharePrice) internal view returns (uint256) {
        uint256 shareUnit = 10 ** vault.decimals();
        uint256 virtualShares = 10 ** vault.decimalsOffset();
        return sharePrice * (vault.totalSupply() + virtualShares) / shareUnit - 1;
    }
}
