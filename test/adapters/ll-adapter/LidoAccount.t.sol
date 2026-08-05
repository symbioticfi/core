// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./AccountsBase.t.sol";

contract LidoAccountTest is AccountsBase {
    function testWstETHAccountPrunesSuccessfulZeroClaim() public {
        MockERC20 stETH = new MockERC20("Liquid staked Ether", "stETH", 18);
        MockWETH weth = new MockWETH();
        MockWstETH wstETH = new MockWstETH(address(stETH));
        MockLidoWithdrawalQueue withdrawalQueue = new MockLidoWithdrawalQueue(address(wstETH), address(stETH));
        MockOracle oracle = new MockOracle(1e18);
        wstETH_Account account = _deployWstETH(wstETH, stETH, weth, withdrawalQueue, oracle);

        wstETH.mint(address(account), 25 ether);
        account.sync();

        withdrawalQueue.setSuccessfulClaim(1, true);
        account.sync();

        vm.expectRevert();
        account.requestIds(0);
    }

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

    function testWstETHAccountReconcilesPendingRequestWhenOracleDiffersFromClaim() public {
        MockERC20 stETH = new MockERC20("Liquid staked Ether", "stETH", 18);
        MockWETH weth = new MockWETH();
        MockWstETH wstETH = new MockWstETH(address(stETH));
        MockLidoWithdrawalQueue withdrawalQueue = new MockLidoWithdrawalQueue(address(wstETH), address(stETH));
        MockOracle oracle = new MockOracle(2e18);
        wstETH_Account account = _deployWstETH(wstETH, stETH, weth, withdrawalQueue, oracle);

        wstETH.mint(address(account), 25 ether);
        account.sync();

        assertEq(account.pendingAssets(), 25 ether);
        assertEq(account.totalAssets(), 25 ether);

        withdrawalQueue.setClaimAmount{value: 25 ether}(1, 25 ether);
        account.sync();

        assertEq(weth.balanceOf(address(account)), 25 ether);
        assertEq(account.pendingAssets(), 0);
        assertEq(account.totalAssets(), 25 ether);
    }

    function testWstETHAccountDerivesPendingAssetsFromWithdrawalStatus() public {
        MockERC20 stETH = new MockERC20("Liquid staked Ether", "stETH", 18);
        MockWETH weth = new MockWETH();
        MockWstETH wstETH = new MockWstETH(address(stETH));
        MockLidoWithdrawalQueue withdrawalQueue = new MockLidoWithdrawalQueue(address(wstETH), address(stETH));
        MockOracle oracle = new MockOracle(1e18);
        wstETH_Account account = _deployWstETH(wstETH, stETH, weth, withdrawalQueue, oracle);

        wstETH.mint(address(account), 25 ether);
        account.sync();

        assertEq(account.pendingAssets(), 25 ether);

        withdrawalQueue.setWithdrawalStatusAmount(1, 17 ether);

        assertEq(account.pendingAssets(), 17 ether);
        assertEq(account.totalAssets(), 17 ether);
    }

    function testWstETHAccountValuesFreshRequestWhenCheckpointHintsRejectRange() public {
        MockERC20 stETH = new MockERC20("Liquid staked Ether", "stETH", 18);
        MockWETH weth = new MockWETH();
        MockWstETH wstETH = new MockWstETH(address(stETH));
        MockLidoWithdrawalQueue withdrawalQueue = new MockLidoWithdrawalQueue(address(wstETH), address(stETH));
        MockOracle oracle = new MockOracle(1e18);
        wstETH_Account account = _deployWstETH(wstETH, stETH, weth, withdrawalQueue, oracle);

        wstETH.mint(address(account), 25 ether);
        account.sync();

        withdrawalQueue.setMaxHintRequestId(0);

        assertEq(account.pendingAssets(), 25 ether);
        assertEq(account.totalAssets(), 25 ether);
    }

    function testWstETHAccountUsesClaimableEtherForFinalizedRequest() public {
        MockERC20 stETH = new MockERC20("Liquid staked Ether", "stETH", 18);
        MockWETH weth = new MockWETH();
        MockWstETH wstETH = new MockWstETH(address(stETH));
        MockLidoWithdrawalQueue withdrawalQueue = new MockLidoWithdrawalQueue(address(wstETH), address(stETH));
        MockOracle oracle = new MockOracle(1e18);
        wstETH_Account account = _deployWstETH(wstETH, stETH, weth, withdrawalQueue, oracle);

        wstETH.mint(address(account), 25 ether);
        account.sync();

        withdrawalQueue.setClaimAmount{value: 17 ether}(1, 17 ether);

        assertEq(account.pendingAssets(), 17 ether);
        assertEq(account.totalAssets(), 17 ether);
    }

    function testWstETHAccountSortsRequestIdsForCheckpointHintsAfterSwapPop() public {
        MockERC20 stETH = new MockERC20("Liquid staked Ether", "stETH", 18);
        MockWETH weth = new MockWETH();
        MockWstETH wstETH = new MockWstETH(address(stETH));
        MockLidoWithdrawalQueue withdrawalQueue = new MockLidoWithdrawalQueue(address(wstETH), address(stETH));
        MockOracle oracle = new MockOracle(1e18);
        wstETH_Account account = _deployWstETH(wstETH, stETH, weth, withdrawalQueue, oracle);

        wstETH.mint(address(account), 2500 ether);
        account.sync();

        withdrawalQueue.setSuccessfulClaim(1, true);
        account.sync();

        assertEq(account.requestIds(0), 3);
        assertEq(account.requestIds(1), 2);
        assertEq(account.pendingAssets(), 1500 ether);
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
        MockWETH weth = new MockWETH();
        MockWstETH wstETH = new MockWstETH(address(stETH));
        MockOracle oracle = new MockOracle(1e18);
        MigratablesFactory factory = new MigratablesFactory(address(this));
        wstETH_Account implementation = new wstETH_Account(
            address(stETH),
            address(weth),
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
