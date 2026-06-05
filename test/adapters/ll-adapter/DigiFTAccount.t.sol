// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import "./AccountsBase.t.sol";

contract DigiFTAccountTest is AccountsBase {
    function testDigiFTAccountForwardsHeldInventoryToRedemptionWallet() public {
        MockERC20 tokenToRedeem = new MockERC20("DigiFT Money Market Fund Token", "DMMF01", 18);
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockOracle oracle = new MockOracle(1e18);
        DigiFTAccount account = _deployDigiFT(tokenToRedeem, asset, oracle);

        tokenToRedeem.mint(address(account), 50 ether);

        assertEq(account.REDEMPTION_WALLET(), redemptionWallet);
        assertEq(account.totalAssets(), 50e6);

        account.sync();

        assertEq(tokenToRedeem.balanceOf(address(account)), 0);
        assertEq(tokenToRedeem.balanceOf(redemptionWallet), 50 ether);
        assertEq(account.totalAssets(), 0);
    }
}
