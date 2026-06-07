// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./AccountsBase.t.sol";

contract HumaAccountTest is AccountsBase {
    function testHumaAccountRequestsAndClaimsTrancheRedemption() public {
        MockERC20 tokenToRedeem = new MockERC20("Huma Senior Tranche", "HST", 18);
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockHumaTrancheVault redemptionVault = new MockHumaTrancheVault(tokenToRedeem, asset);
        MockOracle oracle = new MockOracle(2e18);
        HumaAccount account = _deployHuma(tokenToRedeem, asset, redemptionVault, oracle);

        tokenToRedeem.mint(address(account), 3 ether);

        assertEq(account.totalAssets(), 6e6);

        account.sync();

        assertEq(tokenToRedeem.balanceOf(address(account)), 0);
        assertEq(tokenToRedeem.balanceOf(address(redemptionVault)), 3 ether);
        assertEq(account.pendingAssets(), 6e6);
        assertEq(account.totalAssets(), 6e6);

        redemptionVault.fulfill(address(account), 6e6);
        account.sync();

        assertEq(asset.balanceOf(address(account)), 6e6);
        assertEq(account.pendingAssets(), 0);
        assertEq(account.totalAssets(), 6e6);
    }

    function testHumaAccountClaimsPoolClosureWithdrawal() public {
        MockERC20 tokenToRedeem = new MockERC20("Huma Junior Tranche", "HJT", 18);
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockHumaTrancheVault redemptionVault = new MockHumaTrancheVault(tokenToRedeem, asset);
        MockOracle oracle = new MockOracle(15e17);
        HumaAccount account = _deployHuma(tokenToRedeem, asset, redemptionVault, oracle);

        tokenToRedeem.mint(address(account), 2 ether);

        account.sync();
        redemptionVault.fulfillAfterClosure(address(account), 3e6);
        account.sync();

        assertEq(asset.balanceOf(address(account)), 3e6);
        assertEq(account.pendingAssets(), 0);
        assertEq(account.totalAssets(), 3e6);
    }

    function testPSTAccountHardcodesMainnetTokenAndChainlinkFeed() public {
        vm.mockCall(PST_TOKEN_ADDRESS, abi.encodeWithSignature("decimals()"), abi.encode(uint8(6)));

        MigratablesFactory factory = new MigratablesFactory(address(this));
        address redemptionVault = makeAddr("humaRedemptionVault");
        PST_Account implementation =
            new PST_Account(address(factory), redemptionVault, cowSwapSettlement, cowSwapVaultRelayer);
        ChainlinkOracle oracle = ChainlinkOracle(implementation.ORACLE());

        assertEq(implementation.TOKEN_TO_REDEEM(), PST_TOKEN_ADDRESS);
        assertEq(implementation.REDEMPTION_VAULT(), redemptionVault);
        assertEq(oracle.AGGREGATOR_0(), PST_CHAINLINK_FEED_ADDRESS);
        assertEq(oracle.AGGREGATOR_1(), address(0));
        assertEq(oracle.STALENESS_DURATION_0(), PST_STALENESS_DURATION);
        assertEq(oracle.STALENESS_DURATION_1(), 0);
    }
}
