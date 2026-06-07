// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./AccountsBase.t.sol";

contract AsyncRedeemAccountTest is AccountsBase {
    function testAsyncRedeemAccountDoesNotExposeTotalRequests() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockAsyncRedeemVault tokenToRedeem = new MockAsyncRedeemVault("Centrifuge Share", "CFGSHARE", 18, asset, 2e6);
        MockOracle oracle = new MockOracle(2e18);
        CentrifugeAccount account = _deployCentrifuge(tokenToRedeem, asset, oracle);

        (bool success,) = address(account).staticcall(abi.encodeWithSignature("totalRequests()"));
        assertFalse(success);
    }

    function testAsyncRedeemAccountExposesCowSwapConverter() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockAsyncRedeemVault tokenToRedeem = new MockAsyncRedeemVault("Centrifuge Share", "CFGSHARE", 18, asset, 2e6);
        MockOracle oracle = new MockOracle(2e18);
        CentrifugeAccount account = _deployCentrifuge(tokenToRedeem, asset, oracle);

        (bool success, bytes memory returnData) =
            address(account).staticcall(abi.encodeWithSignature("COW_SWAP_SETTLEMENT()"));
        assertTrue(success);
        assertEq(abi.decode(returnData, (address)), cowSwapSettlement);
    }

    function testAccountTotalAssetsRevertsWhenOracleReturnsZero() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockAsyncRedeemVault tokenToRedeem = new MockAsyncRedeemVault("Centrifuge Share", "CFGSHARE", 18, asset, 2e6);
        MockOracle oracle = new MockOracle(0);
        CentrifugeAccount account = _deployCentrifuge(tokenToRedeem, asset, oracle);

        tokenToRedeem.mint(address(account), 1 ether);

        vm.expectRevert();
        account.totalAssets();
    }

    function testAsyncRedeemAccountDoesNotCapFreshPendingRequestIds() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockAsyncRedeemVault tokenToRedeem = new MockAsyncRedeemVault("Centrifuge Share", "CFGSHARE", 18, asset, 2e6);
        MockOracle oracle = new MockOracle(2e18);
        CentrifugeAccount account = _deployCentrifuge(tokenToRedeem, asset, oracle);
        tokenToRedeem.setFreshRequestIds(true);

        for (uint256 i; i < 25; ++i) {
            tokenToRedeem.mint(address(account), 1 ether);
            account.sync();
        }

        assertEq(tokenToRedeem.nextRequestId(), 25);
        assertEq(tokenToRedeem.balanceOf(address(account)), 0);
        assertEq(account.totalAssets(), 50e6);
    }

    function testAsyncRedeemAccountPermissionlessSyncRespectsCooldown() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockAsyncRedeemVault tokenToRedeem = new MockAsyncRedeemVault("Centrifuge Share", "CFGSHARE", 18, asset, 2e6);
        MockOracle oracle = new MockOracle(2e18);
        CentrifugeAccount account = _deployCentrifuge(tokenToRedeem, asset, oracle, 1 days);
        address keeper = makeAddr("keeper");

        tokenToRedeem.mint(address(account), 1 ether);
        vm.prank(keeper);
        account.sync();

        tokenToRedeem.mint(address(account), 1 ether);
        vm.prank(keeper);
        account.sync();

        assertEq(tokenToRedeem.balanceOf(address(account)), 1 ether);
        assertEq(tokenToRedeem.pending(0, address(account)), 1 ether);
        assertEq(account.totalAssets(), 4e6);

        vm.warp(vm.getBlockTimestamp() + 1 days);
        vm.prank(keeper);
        account.sync();

        assertEq(tokenToRedeem.balanceOf(address(account)), 0);
        assertEq(tokenToRedeem.pending(0, address(account)), 2 ether);
        assertEq(account.totalAssets(), 4e6);
    }

    function testAsyncRedeemAccountOwnerSyncBypassesCooldown() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockAsyncRedeemVault tokenToRedeem = new MockAsyncRedeemVault("Centrifuge Share", "CFGSHARE", 18, asset, 2e6);
        MockOracle oracle = new MockOracle(2e18);
        CentrifugeAccount account = _deployCentrifuge(tokenToRedeem, asset, oracle, 1 days);

        tokenToRedeem.mint(address(account), 1 ether);
        account.sync();

        tokenToRedeem.mint(address(account), 1 ether);
        account.sync();

        assertEq(tokenToRedeem.balanceOf(address(account)), 0);
        assertEq(tokenToRedeem.pending(0, address(account)), 2 ether);
        assertEq(account.totalAssets(), 4e6);
    }
}
