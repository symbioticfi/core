// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./AccountsBase.t.sol";

contract TheoAccountTest is AccountsBase {
    function testTheoAccountInitiatesAndClaimsSthUSDRedeem() public {
        MockERC20 asset = new MockERC20("Theo USD", "thUSD", 6);
        MockSthUSD tokenToRedeem = new MockSthUSD(asset, 1_005_000, 1 days);
        MockOracle oracle = new MockOracle(1_005_000_000_000_000_000);
        TheoAccount account = _deployTheo(tokenToRedeem, asset, oracle);

        tokenToRedeem.mint(address(account), 1000e6);

        assertEq(account.totalAssets(), 1005e6);

        uint256 requestTimestamp = vm.getBlockTimestamp();
        account.sync();

        (uint256 pendingAssets, uint256 pendingShares, uint256 claimableTimestamp) =
            tokenToRedeem.currentRedeemRequest(address(account));
        assertEq(pendingAssets, 1005e6);
        assertEq(pendingShares, 1000e6);
        assertEq(claimableTimestamp, requestTimestamp + 1 days);
        assertEq(tokenToRedeem.balanceOf(address(account)), 0);
        assertEq(asset.balanceOf(address(account)), 0);
        assertEq(account.totalAssets(), 1005e6);

        vm.warp(vm.getBlockTimestamp() + 1 days);
        account.sync();

        (pendingAssets, pendingShares,) = tokenToRedeem.currentRedeemRequest(address(account));
        assertEq(pendingAssets, 0);
        assertEq(pendingShares, 0);
        assertEq(asset.balanceOf(address(account)), 1005e6);
        assertEq(account.totalAssets(), 1005e6);
    }

    function testSthUSDAccountHardcodesCurrentTheoStakedToken() public {
        _mockDecimals(STHUSD_TOKEN_ADDRESS, 6);

        MigratablesFactory factory = new MigratablesFactory(address(this));
        MockOracle oracle = new MockOracle(1e18);
        sthUSD_Account account = new sthUSD_Account(address(oracle), address(factory), cowSwapSettlement);

        assertEq(account.TOKEN_TO_REDEEM(), STHUSD_TOKEN_ADDRESS);
    }
}
