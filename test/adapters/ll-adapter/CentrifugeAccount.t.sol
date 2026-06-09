// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./AccountsBase.t.sol";

contract CentrifugeAccountTest is AccountsBase {
    function testCentrifugeAccountRequestsAndClaimsAsyncRedeemVault() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockAsyncRedeemVault tokenToRedeem = new MockAsyncRedeemVault("Centrifuge Share", "CFGSHARE", 18, asset, 2e6);
        MockOracle oracle = new MockOracle(2e18);
        CentrifugeAccount account = _deployCentrifuge(tokenToRedeem, asset, oracle);

        tokenToRedeem.mint(address(account), 3 ether);

        assertEq(account.totalAssets(), 6e6);

        account.sync();

        assertEq(tokenToRedeem.balanceOf(address(account)), 0);
        assertEq(tokenToRedeem.balanceOf(address(tokenToRedeem)), 3 ether);
        assertEq(account.totalAssets(), 6e6);

        tokenToRedeem.fulfill(0, address(account), 3 ether);
        account.sync();

        assertEq(asset.balanceOf(address(account)), 6e6);
        assertEq(account.totalAssets(), 6e6);
    }

    function testCentrifugeTokenAccountsHardcodeEthereumMainnetTokens() public {
        MigratablesFactory factory = new MigratablesFactory(address(this));
        MockOracle oracle = new MockOracle(1e18);

        _mockDecimals(JTRSY_TOKEN_ADDRESS, 18);
        _mockDecimals(JAAA_TOKEN_ADDRESS, 18);
        _mockDecimals(ACRDX_TOKEN_ADDRESS, 18);
        _mockDecimals(DECRDX_TOKEN_ADDRESS, 18);
        _mockDecimals(DEJTRSY_TOKEN_ADDRESS, 18);
        _mockDecimals(DEJAAA_TOKEN_ADDRESS, 18);

        assertEq(
            new JTRSY_Account(address(oracle), address(factory), cowSwapSettlement).TOKEN_TO_REDEEM(),
            JTRSY_TOKEN_ADDRESS
        );
        assertEq(
            new JAAA_Account(address(oracle), address(factory), cowSwapSettlement).TOKEN_TO_REDEEM(), JAAA_TOKEN_ADDRESS
        );
        assertEq(
            new ACRDX_Account(address(oracle), address(factory), cowSwapSettlement).TOKEN_TO_REDEEM(),
            ACRDX_TOKEN_ADDRESS
        );
        assertEq(
            new deCRDX_Account(address(oracle), address(factory), cowSwapSettlement).TOKEN_TO_REDEEM(),
            DECRDX_TOKEN_ADDRESS
        );
        assertEq(
            new deJTRSY_Account(address(oracle), address(factory), cowSwapSettlement).TOKEN_TO_REDEEM(),
            DEJTRSY_TOKEN_ADDRESS
        );
        assertEq(
            new deJAAA_Account(address(oracle), address(factory), cowSwapSettlement).TOKEN_TO_REDEEM(),
            DEJAAA_TOKEN_ADDRESS
        );
    }
}
