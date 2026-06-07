// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./AccountsBase.t.sol";

contract ThreeJaneAccountTest is AccountsBase {
    function testThreeJaneAccountStartsCooldownAndWithdrawsUSD3() public {
        MockERC20 asset = new MockERC20("3Jane USD3", "USD3", 6);
        MockThreeJaneSUSD3 tokenToRedeem = new MockThreeJaneSUSD3(asset, 1_001_000, 1 days, 2 days);
        MockOracle oracle = new MockOracle(1_001_000_000_000_000_000);
        ThreeJaneAccount account = _deployThreeJane(tokenToRedeem, asset, oracle);

        tokenToRedeem.mint(address(account), 1000e6);

        assertEq(account.totalAssets(), 1001e6);

        uint48 startTimestamp = uint48(vm.getBlockTimestamp());
        account.sync();

        (uint48 cooldownEnd, uint48 windowEnd, uint256 shares) = tokenToRedeem.getCooldownStatus(address(account));
        assertEq(cooldownEnd, startTimestamp + 1 days);
        assertEq(windowEnd, startTimestamp + 3 days);
        assertEq(shares, 1000e6);
        assertEq(tokenToRedeem.balanceOf(address(account)), 1000e6);
        assertEq(asset.balanceOf(address(account)), 0);
        assertEq(account.totalAssets(), 1001e6);

        vm.warp(vm.getBlockTimestamp() + 1 days);
        account.sync();

        assertEq(tokenToRedeem.balanceOf(address(account)), 0);
        assertEq(asset.balanceOf(address(account)), 1001e6);
        assertEq(account.totalAssets(), 1001e6);
    }

    function testThreeJaneAccountWaitsForInitialLockBeforeCooldown() public {
        MockERC20 asset = new MockERC20("3Jane USD3", "USD3", 6);
        MockThreeJaneSUSD3 tokenToRedeem = new MockThreeJaneSUSD3(asset, 1e6, 1 days, 2 days);
        MockOracle oracle = new MockOracle(1e18);
        ThreeJaneAccount account = _deployThreeJane(tokenToRedeem, asset, oracle);

        tokenToRedeem.mint(address(account), 1000e6);
        tokenToRedeem.setLockedUntil(address(account), uint48(vm.getBlockTimestamp() + 1 days));

        account.sync();

        (,, uint256 sharesBeforeLockEnd) = tokenToRedeem.getCooldownStatus(address(account));
        assertEq(sharesBeforeLockEnd, 0);

        vm.warp(vm.getBlockTimestamp() + 1 days);
        account.sync();

        (,, uint256 sharesAfterLockEnd) = tokenToRedeem.getCooldownStatus(address(account));
        assertEq(sharesAfterLockEnd, 1000e6);
    }

    function testSUSD3AccountHardcodesCurrentThreeJaneJuniorToken() public {
        _mockDecimals(SUSD3_TOKEN_ADDRESS, 6);

        MigratablesFactory factory = new MigratablesFactory(address(this));
        MockOracle oracle = new MockOracle(1e18);
        sUSD3_Account account =
            new sUSD3_Account(address(oracle), address(factory), cowSwapSettlement, cowSwapVaultRelayer);

        assertEq(account.TOKEN_TO_REDEEM(), SUSD3_TOKEN_ADDRESS);
    }
}
