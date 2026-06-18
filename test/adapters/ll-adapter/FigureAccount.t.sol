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

        assertEq(prime.balanceOf(address(account)), 0);
        assertEq(wylds.balanceOf(address(wylds)), 125e6);
        assertEq(account.totalAssets(), 125e6);

        wylds.completeFigureRedeem(address(account));
        account.sync();

        assertEq(asset.balanceOf(address(account)), 125e6);
        assertEq(account.totalAssets(), 125e6);
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
