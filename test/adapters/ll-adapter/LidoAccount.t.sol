// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./AccountsBase.t.sol";

contract LidoAccountTest is AccountsBase {
    function testWstETHAccountRequestsWithdrawalAndClaimsWETH() public {
        MockERC20 stETH = new MockERC20("Liquid staked Ether", "stETH", 18);
        MockWETH weth = new MockWETH();
        MockWstETH wstETH = new MockWstETH(address(stETH));
        MockLidoWithdrawalQueue withdrawalQueue = new MockLidoWithdrawalQueue(address(wstETH), address(stETH));
        MockOracle oracle = new MockOracle(1e18);
        wstETH_Account account = _deployWstETH(wstETH, stETH, weth, withdrawalQueue, oracle);

        wstETH.mint(address(account), 25 ether);

        assertEq(account.totalAssets(), 25 ether);

        account.sync();

        assertEq(wstETH.balanceOf(address(account)), 0);
        assertEq(stETH.balanceOf(address(account)), 0);
        assertEq(withdrawalQueue.requestedWstETH(1), 25 ether);
        assertEq(account.totalAssets(), 25 ether);

        withdrawalQueue.setClaimAmount{value: 25 ether}(1, 25 ether);
        account.sync();

        assertEq(weth.balanceOf(address(account)), 25 ether);
        assertEq(address(account).balance, 0);
        assertEq(account.totalAssets(), 25 ether);
    }

    function testWstETHAccountSplitsWithdrawalRequestsAtLidoMax() public {
        MockERC20 stETH = new MockERC20("Liquid staked Ether", "stETH", 18);
        MockWETH weth = new MockWETH();
        MockWstETH wstETH = new MockWstETH(address(stETH));
        MockLidoWithdrawalQueue withdrawalQueue = new MockLidoWithdrawalQueue(address(wstETH), address(stETH));
        MockOracle oracle = new MockOracle(1e18);
        wstETH_Account account = _deployWstETH(wstETH, stETH, weth, withdrawalQueue, oracle);

        wstETH.mint(address(account), 1250 ether);

        account.sync();

        assertEq(withdrawalQueue.requestedWstETH(1), 1000 ether);
        assertEq(withdrawalQueue.requestedWstETH(2), 250 ether);
        assertEq(account.totalAssets(), 1250 ether);
    }

    function testWstETHAccountInitializesWithWETHVaultAsset() public {
        MockERC20 stETH = new MockERC20("Liquid staked Ether", "stETH", 18);
        MockERC20 weth = new MockERC20("Wrapped Ether", "WETH", 18);
        MockWstETH wstETH = new MockWstETH(address(stETH));
        MockOracle oracle = new MockOracle(1e18);
        MigratablesFactory factory = new MigratablesFactory(address(this));
        wstETH_Account implementation = new wstETH_Account(
            address(stETH),
            address(oracle),
            address(wstETH),
            address(factory),
            address(new MockLidoWithdrawalQueue(address(wstETH), address(stETH))),
            cowSwapSettlement
        );
        factory.whitelist(address(implementation));

        wstETH_Account account =
            wstETH_Account(payable(factory.create(1, address(this), _initData(address(weth), address(wstETH)))));

        assertEq(MockVault(account.vault()).asset(), address(weth));
        assertEq(account.totalAssets(), 0);
    }
}
