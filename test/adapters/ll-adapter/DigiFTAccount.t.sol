// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./AccountsBase.t.sol";

import {IDigiFTSubAccount} from "../../../src/interfaces/adapters/ll-adapter/digift/IDigiFTSubAccount.sol";

contract DigiFTAccountTest is AccountsBase {
    function testDigiFTAccountRequestsThroughSubAccountAndSweepsProceeds() public {
        MockERC20 tokenToRedeem = new MockERC20("DigiFT Money Market Fund Token", "DMMF01", 18);
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockOracle oracle = new MockOracle(1e18);
        DigiFTAccount account = _deployDigiFT(tokenToRedeem, asset, oracle);

        tokenToRedeem.mint(address(account), 50 ether);

        assertEq(account.REDEMPTION_WALLET(), redemptionWallet);
        assertEq(account.PENDING_ASSETS_DURATION(), DIGIFT_PENDING_ASSETS_DURATION);
        assertEq(account.totalAssets(), 50e6);

        account.sync();

        address subAccount = account.subAccounts(0);

        assertEq(tokenToRedeem.balanceOf(address(account)), 0);
        assertEq(tokenToRedeem.balanceOf(subAccount), 0);
        assertEq(tokenToRedeem.balanceOf(redemptionWallet), 50 ether);
        assertEq(account.totalAssets(), 50e6);
        assertEq(IDigiFTSubAccount(subAccount).totalAssets(), 50e6);

        asset.mint(subAccount, 50e6);
        account.sync();

        assertEq(asset.balanceOf(address(account)), 50e6);
        assertEq(account.totalAssets(), 50e6);

        vm.expectRevert();
        account.subAccounts(0);
    }

    function testDigiFTAccountKeepsSubAccountPendingUntilFullySettled() public {
        MockERC20 tokenToRedeem = new MockERC20("DigiFT Money Market Fund Token", "DMMF01", 18);
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockOracle oracle = new MockOracle(1e18);
        DigiFTAccount account = _deployDigiFT(tokenToRedeem, asset, oracle);

        tokenToRedeem.mint(address(account), 50 ether);
        account.sync();

        address subAccount = account.subAccounts(0);

        asset.mint(subAccount, 20e6);
        account.sync();

        assertEq(asset.balanceOf(address(account)), 20e6);
        assertEq(account.subAccounts(0), subAccount);
        assertEq(IDigiFTSubAccount(subAccount).totalAssets(), 30e6);
        assertEq(account.totalAssets(), 50e6);

        asset.mint(subAccount, 30e6);
        account.sync();

        assertEq(asset.balanceOf(address(account)), 50e6);
        assertEq(account.totalAssets(), 50e6);

        vm.expectRevert();
        account.subAccounts(0);
    }

    function testDigiFTAccountStopsCountingStalePendingAssets() public {
        MockERC20 tokenToRedeem = new MockERC20("DigiFT Money Market Fund Token", "DMMF01", 18);
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockOracle oracle = new MockOracle(1e18);
        DigiFTAccount account = _deployDigiFT(tokenToRedeem, asset, oracle);

        tokenToRedeem.mint(address(account), 50 ether);
        account.sync();

        address subAccount = account.subAccounts(0);

        asset.mint(subAccount, 20e6);
        account.sync();

        assertEq(asset.balanceOf(address(account)), 20e6);
        assertEq(account.totalAssets(), 50e6);

        vm.warp(vm.getBlockTimestamp() + DIGIFT_PENDING_ASSETS_DURATION);

        assertEq(IDigiFTSubAccount(subAccount).totalAssets(), 0);
        assertEq(account.totalAssets(), 20e6);

        account.sync();

        assertEq(asset.balanceOf(address(account)), 20e6);
        assertEq(account.totalAssets(), 20e6);

        vm.expectRevert();
        account.subAccounts(0);
    }

    function testDigiFTSubAccountOnlyParentCanSync() public {
        MockERC20 tokenToRedeem = new MockERC20("DigiFT Money Market Fund Token", "DMMF01", 18);
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockOracle oracle = new MockOracle(1e18);
        DigiFTAccount account = _deployDigiFT(tokenToRedeem, asset, oracle);

        tokenToRedeem.mint(address(account), 50 ether);
        account.sync();

        address subAccount = account.subAccounts(0);

        vm.expectRevert(IDigiFTSubAccount.NotAccount.selector);
        IDigiFTSubAccount(subAccount).sync();
    }
}
