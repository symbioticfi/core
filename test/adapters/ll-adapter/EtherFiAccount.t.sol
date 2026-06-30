// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./AccountsBase.t.sol";

import {IEtherFiAccount} from "../../../src/interfaces/adapters/ll-adapter/etherfi/IEtherFiAccount.sol";

contract EtherFiAccountTest is AccountsBase {
    function testWeETHAccountPrunesSuccessfulZeroClaim() public {
        LstMocks memory mocks = _lstMocks();
        MockOracle oracle = new MockOracle(1e18);
        weETH_Account account = _deployWeETH(mocks, mocks.weth, oracle);

        mocks.weETH.mint(address(account), 6 ether);
        account.sync();

        mocks.withdrawRequestNft.setClaimSucceeds(1, true);
        account.sync();

        vm.expectRevert();
        account.requestIds(0);
    }

    function testWeETHAccountQueuesWithdrawalWhenInstantWETHIsUnavailable() public {
        LstMocks memory mocks = _lstMocks();
        MockOracle oracle = new MockOracle(1e18);
        weETH_Account account = _deployWeETH(mocks, mocks.weth, oracle);

        mocks.weETH.mint(address(account), 12 ether);

        account.sync();

        assertEq(mocks.weETH.balanceOf(address(account)), 0);
        assertEq(mocks.stETH.balanceOf(address(account)), 0);
        assertEq(mocks.eETH.balanceOf(address(mocks.liquidityPool)), 12 ether);
        assertEq(mocks.redemptionManager.lastOutputToken(), address(0));
        assertEq(mocks.liquidityPool.lastAmount(), 12 ether);
        assertEq(account.totalAssets(), 12 ether);
    }

    function testWeETHAccountInstantRedeemsIntoWETHWhenVaultAssetIsWETH() public {
        LstMocks memory mocks = _lstMocks();
        MockOracle oracle = new MockOracle(1e18);
        weETH_Account account = _deployWeETH(mocks, mocks.weth, oracle);
        address ethAddress = mocks.redemptionManager.ETH_ADDRESS();

        mocks.weETH.mint(address(account), 9 ether);
        mocks.redemptionManager.setExitFee(ethAddress, 0);
        mocks.redemptionManager.setRedeemable(ethAddress, true);
        vm.deal(address(mocks.redemptionManager), 9 ether);

        account.sync();

        assertEq(mocks.weETH.balanceOf(address(account)), 0);
        assertEq(mocks.stETH.balanceOf(address(account)), 0);
        assertEq(mocks.weth.balanceOf(address(account)), 9 ether);
        assertEq(mocks.redemptionManager.lastOutputToken(), ethAddress);
        assertEq(mocks.liquidityPool.lastAmount(), 0);
        assertEq(account.totalAssets(), 9 ether);
    }

    function testWeETHAccountInstantRedeemWrapsOnlyClaimedEth() public {
        LstMocks memory mocks = _lstMocks();
        MockOracle oracle = new MockOracle(1e18);
        weETH_Account account = _deployWeETH(mocks, mocks.weth, oracle);
        address ethAddress = mocks.redemptionManager.ETH_ADDRESS();

        mocks.weETH.mint(address(account), 9 ether);
        vm.deal(address(account), 1 ether);
        mocks.redemptionManager.setExitFee(ethAddress, 0);
        mocks.redemptionManager.setRedeemable(ethAddress, true);
        vm.deal(address(mocks.redemptionManager), 9 ether);

        account.sync();

        assertEq(mocks.weth.balanceOf(address(account)), 9 ether);
        assertEq(address(account).balance, 1 ether);
        assertEq(account.totalAssets(), 9 ether);
    }

    function testWeETHAccountQueuesWithdrawalWhenInstantRedeemReverts() public {
        LstMocks memory mocks = _lstMocks();
        MockOracle oracle = new MockOracle(1e18);
        weETH_Account account = _deployWeETH(mocks, mocks.weth, oracle);
        address ethAddress = mocks.redemptionManager.ETH_ADDRESS();

        mocks.weETH.mint(address(account), 4 ether);
        mocks.redemptionManager.setExitFee(ethAddress, 0);
        mocks.redemptionManager.setRedeemable(ethAddress, true);
        mocks.redemptionManager.setRevertRedeem(true);

        account.sync();

        assertEq(mocks.eETH.balanceOf(address(mocks.liquidityPool)), 4 ether);
        assertEq(mocks.liquidityPool.lastRecipient(), address(account));
        assertEq(mocks.liquidityPool.lastAmount(), 4 ether);
        assertEq(mocks.redemptionManager.lastWeETHAmount(), 0);
        assertEq(account.pendingAssets(), 4 ether);
        assertEq(account.totalAssets(), 4 ether);
    }

    function testWeETHAccountQueuesWithdrawalAndClaimWrapsIntoWETH() public {
        LstMocks memory mocks = _lstMocks();
        MockOracle oracle = new MockOracle(1e18);
        weETH_Account account = _deployWeETH(mocks, mocks.weth, oracle);

        mocks.weETH.mint(address(account), 15 ether);

        account.sync();

        assertEq(mocks.eETH.balanceOf(address(mocks.liquidityPool)), 15 ether);
        assertEq(mocks.liquidityPool.lastRecipient(), address(account));
        assertEq(mocks.liquidityPool.lastAmount(), 15 ether);
        assertEq(account.totalAssets(), 15 ether);
        assertEq(account.pendingAssets(), 15 ether);

        mocks.withdrawRequestNft.setClaimAmount{value: 15 ether}(15 ether);
        account.claimWithdraw(1);

        assertEq(mocks.weth.balanceOf(address(account)), 15 ether);
        assertEq(address(account).balance, 0);
        assertEq(account.pendingAssets(), 0);
        assertEq(account.totalAssets(), 15 ether);
    }

    function testWeETHAccountQueuedClaimWrapsOnlyClaimedEth() public {
        LstMocks memory mocks = _lstMocks();
        MockOracle oracle = new MockOracle(1e18);
        weETH_Account account = _deployWeETH(mocks, mocks.weth, oracle);

        mocks.weETH.mint(address(account), 6 ether);
        account.sync();

        vm.deal(address(account), 1 ether);
        mocks.withdrawRequestNft.setClaimAmount{value: 6 ether}(6 ether);
        account.claimWithdraw(1);

        assertEq(mocks.weth.balanceOf(address(account)), 6 ether);
        assertEq(address(account).balance, 1 ether);
        assertEq(account.pendingAssets(), 0);
        assertEq(account.totalAssets(), 6 ether);
    }

    function testWeETHAccountReconcilesPendingRequestWhenOracleDiffersFromClaim() public {
        LstMocks memory mocks = _lstMocks();
        MockOracle oracle = new MockOracle(2e18);
        weETH_Account account = _deployWeETH(mocks, mocks.weth, oracle);

        mocks.weETH.mint(address(account), 6 ether);
        account.sync();

        assertEq(account.pendingAssets(), 6 ether);
        assertEq(account.totalAssets(), 6 ether);

        mocks.withdrawRequestNft.setClaimAmount{value: 6 ether}(6 ether);
        account.sync();

        assertEq(mocks.weth.balanceOf(address(account)), 6 ether);
        assertEq(account.pendingAssets(), 0);
        assertEq(account.totalAssets(), 6 ether);
    }

    function testWeETHAccountDerivesPendingAssetsFromRequestData() public {
        LstMocks memory mocks = _lstMocks();
        MockOracle oracle = new MockOracle(1e18);
        weETH_Account account = _deployWeETH(mocks, mocks.weth, oracle);

        mocks.weETH.mint(address(account), 6 ether);
        account.sync();

        assertEq(account.pendingAssets(), 6 ether);

        mocks.liquidityPool.setAmountForShareRate(0.5e18);

        assertEq(account.pendingAssets(), 3 ether);
        assertEq(account.totalAssets(), 3 ether);
    }

    function testWeETHAccountSyncClaimsQueuedWithdrawal() public {
        LstMocks memory mocks = _lstMocks();
        MockOracle oracle = new MockOracle(1e18);
        weETH_Account account = _deployWeETH(mocks, mocks.weth, oracle);

        mocks.weETH.mint(address(account), 6 ether);
        mocks.redemptionManager.setExitFee(mocks.redemptionManager.ETH_ADDRESS(), 25);

        account.sync();

        assertEq(account.pendingAssets(), 6 ether);

        mocks.withdrawRequestNft.setClaimAmount{value: 6 ether}(6 ether);
        account.sync();

        assertEq(mocks.weth.balanceOf(address(account)), 6 ether);
        assertEq(account.pendingAssets(), 0);
        assertEq(account.totalAssets(), 6 ether);
    }

    function testWeETHAccountDoesNotExposeTotalRequests() public {
        LstMocks memory mocks = _lstMocks();
        MockOracle oracle = new MockOracle(1e18);
        weETH_Account account = _deployWeETH(mocks, mocks.weth, oracle);

        (bool success,) = address(account).staticcall(abi.encodeCall(ILegacyTotalRequests.totalRequests, ()));
        assertFalse(success);
    }

    function testWeETHAccountQueuesWithdrawalWhenInstantETHIsUnavailable() public {
        LstMocks memory mocks = _lstMocks();
        MockOracle oracle = new MockOracle(1e18);
        weETH_Account account = _deployWeETH(mocks, mocks.weth, oracle);

        mocks.weETH.mint(address(account), 4 ether);
        mocks.redemptionManager.setExitFee(mocks.redemptionManager.ETH_ADDRESS(), 0);
        mocks.redemptionManager.setRedeemable(mocks.redemptionManager.ETH_ADDRESS(), false);

        account.sync();

        assertEq(mocks.eETH.balanceOf(address(mocks.liquidityPool)), 4 ether);
        assertEq(mocks.liquidityPool.lastRecipient(), address(account));
        assertEq(mocks.liquidityPool.lastAmount(), 4 ether);
        assertEq(mocks.redemptionManager.lastWeETHAmount(), 0);
        assertEq(account.pendingAssets(), 4 ether);
        assertEq(account.totalAssets(), 4 ether);
    }

    function testWeETHAccountQueuesWithdrawalWhenOracleReturnsZero() public {
        LstMocks memory mocks = _lstMocks();
        MockOracle oracle = new MockOracle(0);
        weETH_Account account = _deployWeETH(mocks, mocks.weth, oracle);

        mocks.weETH.mint(address(account), 4 ether);
        mocks.redemptionManager.setExitFee(mocks.redemptionManager.ETH_ADDRESS(), 0);
        mocks.redemptionManager.setRedeemable(mocks.redemptionManager.ETH_ADDRESS(), false);

        account.sync();

        assertEq(mocks.eETH.balanceOf(address(mocks.liquidityPool)), 4 ether);
        assertEq(mocks.liquidityPool.lastRecipient(), address(account));
        assertEq(mocks.liquidityPool.lastAmount(), 4 ether);
        assertEq(account.pendingAssets(), 4 ether);
        assertEq(account.totalAssets(), 4 ether);
    }

    function testWeETHAccountRejectsNonWETHVaultAsset() public {
        LstMocks memory mocks = _lstMocks();
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockOracle oracle = new MockOracle(1e18);
        MigratablesFactory factory = new MigratablesFactory(address(this));
        weETH_Account implementation = new weETH_Account(
            address(mocks.eETH),
            address(mocks.weth),
            address(mocks.weETH),
            address(oracle),
            address(factory),
            address(mocks.liquidityPool),
            address(mocks.redemptionManager),
            cowSwapSettlement,
            address(mocks.withdrawRequestNft)
        );
        factory.whitelist(address(implementation));

        bytes memory data = _initData(address(asset), address(mocks.weETH));

        vm.expectRevert(IEtherFiAccount.InvalidAsset.selector);
        factory.create(1, address(this), data);
    }
}
