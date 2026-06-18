// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./AccountsBase.t.sol";

import {CentrifugeAccount} from "../../../src/contracts/adapters/ll-adapter/CentrifugeAccount.sol";

contract AsyncRedeemAccountTest is AccountsBase {
    function testAsyncRedeemOracleUsesAsyncVaultConversion() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockAsyncRedeemVault tokenToRedeem = new MockAsyncRedeemVault("Centrifuge Share", "CFGSHARE", 18, asset, 2e6);
        AsyncRedeemOracle oracle = new AsyncRedeemOracle(address(tokenToRedeem));

        assertEq(oracle.ASYNC_REDEEM_VAULT(), address(tokenToRedeem));
        assertEq(oracle.getPrice(), 2e18);
    }

    function testAsyncRedeemAccountValuesHeldSharesWithAsyncVaultConversion() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockAsyncRedeemVault tokenToRedeem = new MockAsyncRedeemVault("Centrifuge Share", "CFGSHARE", 18, asset, 2e6);
        AsyncRedeemOracle oracle = new AsyncRedeemOracle(address(tokenToRedeem));
        TestAsyncRedeemAccount account = _deployAsyncRedeem(tokenToRedeem, asset, oracle);

        tokenToRedeem.mint(address(account), 1 ether);

        assertEq(account.totalAssets(), 2e6);

        account.sync();

        assertEq(account.totalAssets(), 2e6);
    }

    function testAsyncRedeemAccountTotalAssetsUsesConvertWhenPreviewWithdrawReverts() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockAsyncRedeemVault tokenToRedeem = new MockAsyncRedeemVault("Centrifuge Share", "CFGSHARE", 18, asset, 2e6);
        MockOracle oracle = new MockOracle(2e18);
        TestAsyncRedeemAccount account = _deployAsyncRedeem(tokenToRedeem, asset, oracle);

        tokenToRedeem.mint(address(account), 1 ether);
        account.sync();
        tokenToRedeem.setRevertPreviewWithdraw(true);

        assertEq(account.totalAssets(), 2e6);
    }

    function testAsyncRedeemAccountDoesNotExposeTotalRequests() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockAsyncRedeemVault tokenToRedeem = new MockAsyncRedeemVault("Centrifuge Share", "CFGSHARE", 18, asset, 2e6);
        MockOracle oracle = new MockOracle(2e18);
        TestAsyncRedeemAccount account = _deployAsyncRedeem(tokenToRedeem, asset, oracle);

        (bool success,) = address(account).staticcall(abi.encodeWithSignature("totalRequests()"));
        assertFalse(success);
    }

    function testAsyncRedeemAccountExposesCowSwapConverter() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockAsyncRedeemVault tokenToRedeem = new MockAsyncRedeemVault("Centrifuge Share", "CFGSHARE", 18, asset, 2e6);
        MockOracle oracle = new MockOracle(2e18);
        TestAsyncRedeemAccount account = _deployAsyncRedeem(tokenToRedeem, asset, oracle);

        (bool success, bytes memory returnData) =
            address(account).staticcall(abi.encodeWithSignature("COW_SWAP_SETTLEMENT()"));
        assertTrue(success);
        assertEq(abi.decode(returnData, (address)), cowSwapSettlement);
    }

    function testAsyncRedeemAccountRevertsWhenOracleReturnsZero() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockAsyncRedeemVault tokenToRedeem = new MockAsyncRedeemVault("Centrifuge Share", "CFGSHARE", 18, asset, 2e6);
        MockOracle oracle = new MockOracle(0);
        TestAsyncRedeemAccount account = _deployAsyncRedeem(tokenToRedeem, asset, oracle);

        tokenToRedeem.mint(address(account), 1 ether);

        vm.expectRevert(IAccount.InvalidOracle.selector);
        account.totalAssets();
    }

    function testAsyncRedeemAccountDoesNotCapFreshPendingRequestIds() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockAsyncRedeemVault tokenToRedeem = new MockAsyncRedeemVault("Centrifuge Share", "CFGSHARE", 18, asset, 2e6);
        MockOracle oracle = new MockOracle(2e18);
        TestAsyncRedeemAccount account = _deployAsyncRedeem(tokenToRedeem, asset, oracle);
        tokenToRedeem.setFreshRequestIds(true);

        for (uint256 i; i < 25; ++i) {
            tokenToRedeem.mint(address(account), 1 ether);
            account.sync();
        }

        assertEq(tokenToRedeem.nextRequestId(), 25);
        assertEq(tokenToRedeem.balanceOf(address(account)), 0);
        assertEq(account.totalAssets(), 50e6);
    }

    function testAsyncRedeemAccountStoresUint64RequestIds() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockAsyncRedeemVault tokenToRedeem = new MockAsyncRedeemVault("Centrifuge Share", "CFGSHARE", 18, asset, 2e6);
        MockOracle oracle = new MockOracle(2e18);
        TestAsyncRedeemAccount account = _deployAsyncRedeem(tokenToRedeem, asset, oracle);
        tokenToRedeem.setFreshRequestIds(true);

        tokenToRedeem.mint(address(account), 1 ether);
        account.sync();

        uint64 requestId = account.requestIds(0);

        assertEq(requestId, 0);
        assertEq(tokenToRedeem.pending(requestId, address(account)), 1 ether);
        assertEq(account.totalAssets(), 2e6);
    }

    function testAsyncRedeemAccountPermissionlessSyncRespectsCooldown() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockAsyncRedeemVault tokenToRedeem = new MockAsyncRedeemVault("Centrifuge Share", "CFGSHARE", 18, asset, 2e6);
        MockOracle oracle = new MockOracle(2e18);
        TestAsyncRedeemAccount account = _deployAsyncRedeem(tokenToRedeem, asset, oracle, 1 days);
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
        TestAsyncRedeemAccount account = _deployAsyncRedeem(tokenToRedeem, asset, oracle, 1 days);

        tokenToRedeem.mint(address(account), 1 ether);
        account.sync();

        tokenToRedeem.mint(address(account), 1 ether);
        account.sync();

        assertEq(tokenToRedeem.balanceOf(address(account)), 0);
        assertEq(tokenToRedeem.pending(0, address(account)), 2 ether);
        assertEq(account.totalAssets(), 4e6);
    }

    function testAsyncRedeemAccountRequestsAndClaimsAsyncRedeemVault() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockAsyncRedeemVault tokenToRedeem = new MockAsyncRedeemVault("Centrifuge Share", "CFGSHARE", 18, asset, 2e6);
        MockOracle oracle = new MockOracle(2e18);
        TestAsyncRedeemAccount account = _deployAsyncRedeem(tokenToRedeem, asset, oracle);

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

    function testAsyncRedeemAccountValuesClaimableLegAtFulfillmentPrice() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockAsyncRedeemVault tokenToRedeem = new MockAsyncRedeemVault("Centrifuge Share", "CFGSHARE", 18, asset, 2e6);
        MockOracle oracle = new MockOracle(2e18);
        TestAsyncRedeemAccount account = _deployAsyncRedeem(tokenToRedeem, asset, oracle);
        tokenToRedeem.setFreshRequestIds(true);

        tokenToRedeem.mint(address(account), 1 ether);
        account.sync();

        tokenToRedeem.mint(address(account), 1 ether);
        account.sync();

        // request 0 is fulfilled at 2e6 assets per share, request 1 stays pending
        tokenToRedeem.fulfill(0, address(account), 1 ether);

        // live price doubles after fulfillment
        tokenToRedeem.setAssetsPerShare(4e6);

        // claimable leg stays frozen at the fulfillment price (2e6), pending leg follows the live price (4e6)
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

    function testCentrifugeTokenAccountsUseCentrifugeAccountBase() public {
        MigratablesFactory factory = new MigratablesFactory(address(this));
        MockOracle oracle = new MockOracle(1e18);

        _mockDecimals(JTRSY_TOKEN_ADDRESS, 18);
        _mockDecimals(JAAA_TOKEN_ADDRESS, 18);
        _mockDecimals(ACRDX_TOKEN_ADDRESS, 18);
        _mockDecimals(DECRDX_TOKEN_ADDRESS, 18);
        _mockDecimals(DEJTRSY_TOKEN_ADDRESS, 18);
        _mockDecimals(DEJAAA_TOKEN_ADDRESS, 18);

        assertEq(
            IAccount(_centrifugeAccountAddress(new JTRSY_Account(address(oracle), address(factory), cowSwapSettlement)))
                .TOKEN_TO_REDEEM(),
            JTRSY_TOKEN_ADDRESS
        );
        assertEq(
            IAccount(_centrifugeAccountAddress(new JAAA_Account(address(oracle), address(factory), cowSwapSettlement)))
                .TOKEN_TO_REDEEM(),
            JAAA_TOKEN_ADDRESS
        );
        assertEq(
            IAccount(_centrifugeAccountAddress(new ACRDX_Account(address(oracle), address(factory), cowSwapSettlement)))
                .TOKEN_TO_REDEEM(),
            ACRDX_TOKEN_ADDRESS
        );
        assertEq(
            IAccount(
                    _centrifugeAccountAddress(new deCRDX_Account(address(oracle), address(factory), cowSwapSettlement))
                ).TOKEN_TO_REDEEM(),
            DECRDX_TOKEN_ADDRESS
        );
        assertEq(
            IAccount(
                    _centrifugeAccountAddress(new deJTRSY_Account(address(oracle), address(factory), cowSwapSettlement))
                ).TOKEN_TO_REDEEM(),
            DEJTRSY_TOKEN_ADDRESS
        );
        assertEq(
            IAccount(
                    _centrifugeAccountAddress(new deJAAA_Account(address(oracle), address(factory), cowSwapSettlement))
                ).TOKEN_TO_REDEEM(),
            DEJAAA_TOKEN_ADDRESS
        );
    }

    function _centrifugeAccountAddress(CentrifugeAccount account) internal pure returns (address) {
        return address(account);
    }
}
