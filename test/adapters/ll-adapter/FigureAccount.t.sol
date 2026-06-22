// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./AccountsBase.t.sol";

contract FigureAccountTest is AccountsBase {
    function testFigureAccountTotalAssetsUsesConvertWhenPreviewWithdrawReverts() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockAsyncRedeemVault wylds = new MockAsyncRedeemVault("Wrapped YLDS", "wYLDS", 6, asset, 1e6);
        MockPrimeToken prime = new MockPrimeToken(wylds, 125e4);
        AsyncRedeemOracle oracle = new AsyncRedeemOracle(address(wylds));
        PRIME_Account account = _deployPrime(prime, asset, oracle);

        wylds.mint(address(account), 125e6);
        wylds.setRevertPreviewWithdraw(true);

        assertEq(account.totalAssets(), 125e6);
    }

    function testFigureAccountInstantRedeemsPrimeThenRequestsWyldsRedeem() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockAsyncRedeemVault wylds = new MockAsyncRedeemVault("Wrapped YLDS", "wYLDS", 6, asset, 1e6);
        MockPrimeToken prime = new MockPrimeToken(wylds, 125e4);
        AsyncRedeemOracle oracle = new AsyncRedeemOracle(address(wylds));
        PRIME_Account account = _deployPrime(prime, asset, oracle);

        prime.mint(address(account), 100e6);

        assertEq(account.totalAssets(), 125e6);

        account.sync();

        address subAccount = account.subAccounts(0);

        assertEq(prime.balanceOf(address(account)), 0);
        assertEq(wylds.balanceOf(address(wylds)), 125e6);
        assertEq(wylds.balanceOf(subAccount), 0);
        assertEq(account.totalAssets(), 125e6);

        wylds.completeFigureRedeem(subAccount);
        account.sync();

        assertEq(asset.balanceOf(address(account)), 125e6);
        assertEq(account.totalAssets(), 125e6);
    }

    function testFigureAccountCreatesSubAccountPerCloseRequest() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockAsyncRedeemVault wylds = new MockAsyncRedeemVault("Wrapped YLDS", "wYLDS", 6, asset, 1e6);
        MockPrimeToken prime = new MockPrimeToken(wylds, 125e4);
        AsyncRedeemOracle oracle = new AsyncRedeemOracle(address(wylds));
        PRIME_Account account = _deployPrime(prime, asset, oracle);

        prime.mint(address(account), 100e6);
        account.sync();

        address firstSubAccount = account.subAccounts(0);

        prime.mint(address(account), 40e6);
        account.sync();

        address secondSubAccount = account.subAccounts(1);

        (uint256 firstShares, uint256 firstAssets,) = wylds.pendingRedemptions(firstSubAccount);
        (uint256 secondShares, uint256 secondAssets,) = wylds.pendingRedemptions(secondSubAccount);
        assertNotEq(secondSubAccount, firstSubAccount);
        assertEq(firstShares, 125e6);
        assertEq(firstAssets, 125e6);
        assertEq(secondShares, 50e6);
        assertEq(secondAssets, 50e6);
        assertEq(account.totalAssets(), 175e6);

        wylds.completeFigureRedeem(firstSubAccount);
        account.sync();

        assertEq(asset.balanceOf(address(account)), 125e6);
        assertEq(account.subAccounts(0), secondSubAccount);
        assertEq(account.totalAssets(), 175e6);

        wylds.completeFigureRedeem(secondSubAccount);
        account.sync();

        assertEq(asset.balanceOf(address(account)), 175e6);
        vm.expectRevert();
        account.subAccounts(0);
        assertEq(account.totalAssets(), 175e6);
    }

    function testFigureAccountDoesNotPruneActiveZeroAssetRequest() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockAsyncRedeemVault wylds = new MockAsyncRedeemVault("Wrapped YLDS", "wYLDS", 6, asset, 0);
        MockPrimeToken prime = new MockPrimeToken(wylds, 1e6);
        AsyncRedeemOracle oracle = new AsyncRedeemOracle(address(wylds));
        PRIME_Account account = _deployPrime(prime, asset, oracle);

        prime.mint(address(account), 1e6);
        account.sync();

        address subAccount = account.subAccounts(0);
        (, uint256 pendingAssets,) = wylds.pendingRedemptions(subAccount);
        assertEq(pendingAssets, 0);

        account.sync();

        assertEq(account.subAccounts(0), subAccount);
    }

    function testFigureSubAccountOnlyExposesRequestAndFinalizeRedeem() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockAsyncRedeemVault wylds = new MockAsyncRedeemVault("Wrapped YLDS", "wYLDS", 6, asset, 1e6);
        MockPrimeToken prime = new MockPrimeToken(wylds, 125e4);
        AsyncRedeemOracle oracle = new AsyncRedeemOracle(address(wylds));
        PRIME_Account account = _deployPrime(prime, asset, oracle);

        prime.mint(address(account), 100e6);
        account.sync();

        address subAccount = account.subAccounts(0);

        (bool success,) = subAccount.staticcall(abi.encodeWithSignature("totalAssets()"));
        assertFalse(success);

        wylds.completeFigureRedeem(subAccount);

        vm.prank(address(account));
        (success,) = subAccount.call(abi.encodeWithSignature("finalizeRedeem()"));
        assertTrue(success);

        assertEq(asset.balanceOf(address(account)), 125e6);
    }

    function testFigureAccountKeepsWyldsWhenVaultAssetMatches() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockAsyncRedeemVault wylds = new MockAsyncRedeemVault("Wrapped YLDS", "wYLDS", 6, asset, 1e6);
        MockPrimeToken prime = new MockPrimeToken(wylds, 125e4);
        MockOracle oracle = new MockOracle(1e18);
        PRIME_Account account = _deployPrime(prime, wylds, oracle);

        prime.mint(address(account), 100e6);

        assertEq(account.totalAssets(), 125e6);

        account.sync();

        assertEq(prime.balanceOf(address(account)), 0);
        assertEq(wylds.balanceOf(address(account)), 125e6);
        assertEq(wylds.balanceOf(address(wylds)), 0);
        assertEq(account.totalAssets(), 125e6);
    }
}
