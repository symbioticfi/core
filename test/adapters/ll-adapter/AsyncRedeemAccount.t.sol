// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./AccountsBase.t.sol";

import {CentrifugeAccount} from "../../../src/contracts/adapters/ll-adapter/CentrifugeAccount.sol";
import {ICoWSwapConverter} from "../../../src/interfaces/adapters/common/ICoWSwapConverter.sol";
import {IERC7575Share} from "../../../src/interfaces/adapters/ll-adapter/IERC7575Share.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract AsyncRedeemAccountTest is AccountsBase {
    function testBaseAsyncRedeemAccountUsesTokenAsVault() public {
        MockERC20 tokenToRedeem = new MockERC20("Async Vault", "ASYNC", 18);
        MockOracle oracle = new MockOracle(1e18);
        MigratablesFactory factory = new MigratablesFactory(address(this));
        TestBaseAsyncRedeemAccount account = new TestBaseAsyncRedeemAccount(
            address(oracle), address(factory), address(tokenToRedeem), address(tokenToRedeem), cowSwapSettlement
        );

        assertEq(account.asyncRedeemVault(), address(tokenToRedeem));
    }

    function testCentrifugeAccountUsesAssetSpecificERC7575Vault() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 share = new MockERC20("Centrifuge Share", "CFGSHARE", 18);
        MockAsyncRedeemVault vault = new MockAsyncRedeemVault("Centrifuge Vault", "CFGV", 18, asset, 2e6);
        MockOracle oracle = new MockOracle(2e18);
        vm.mockCall(address(share), abi.encodeCall(IERC7575Share.vault, (address(asset))), abi.encode(address(vault)));
        TestAsyncRedeemAccount account = _deployAsyncRedeem(address(share), asset, oracle, 0);

        assertEq(account.asyncRedeemVault(), address(vault));
    }

    function testAsyncRedeemOracleUsesAsyncVaultConversion() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockAsyncRedeemVault tokenToRedeem = new MockAsyncRedeemVault("Centrifuge Share", "CFGSHARE", 18, asset, 2e6);
        AsyncRedeemOracle oracle =
            new AsyncRedeemOracle(1, type(uint256).max, address(tokenToRedeem), address(tokenToRedeem));

        assertEq(oracle.ASYNC_REDEEM_VAULT(), address(tokenToRedeem));
        assertEq(oracle.getPrice(), 2e18);
    }

    function testAsyncRedeemOracleUsesTokenDecimalsWhenVaultHasNoDecimals() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 tokenToRedeem = new MockERC20("Centrifuge Share", "CFGSHARE", 18);
        MockAsyncRedeemVaultWithoutDecimals asyncRedeemVault =
            new MockAsyncRedeemVaultWithoutDecimals(asset, tokenToRedeem, 2e6);
        AsyncRedeemOracle oracle =
            new AsyncRedeemOracle(1, type(uint256).max, address(tokenToRedeem), address(asyncRedeemVault));

        (bool success,) = address(asyncRedeemVault).staticcall(abi.encodeCall(IERC20Metadata.decimals, ()));

        assertFalse(success);
        assertEq(oracle.ASYNC_REDEEM_VAULT(), address(asyncRedeemVault));
        assertEq(oracle.getPrice(), 2e18);
    }

    function testAsyncRedeemAccountValuesHeldSharesWithAsyncVaultConversion() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockAsyncRedeemVault tokenToRedeem = new MockAsyncRedeemVault("Centrifuge Share", "CFGSHARE", 18, asset, 2e6);
        AsyncRedeemOracle oracle =
            new AsyncRedeemOracle(1, type(uint256).max, address(tokenToRedeem), address(tokenToRedeem));
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

    function testAsyncRedeemAccountValuesPendingRequestsAtOraclePrice() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockAsyncRedeemVault tokenToRedeem = new MockAsyncRedeemVault("Centrifuge Share", "CFGSHARE", 18, asset, 2e6);
        MockOracle oracle = new MockOracle(3e18);
        TestAsyncRedeemAccount account = _deployAsyncRedeem(tokenToRedeem, asset, oracle);

        tokenToRedeem.mint(address(account), 1 ether);
        account.sync();

        assertEq(tokenToRedeem.convertToAssets(1 ether), 2e6);
        assertEq(account.totalAssets(), 3e6);
    }

    function testBaseAsyncRedeemAccountSupportsDifferentRedemptionAndAccountAssets() public {
        MockERC20 accountAsset = new MockERC20("Tether USD", "USDT", 6);
        MockERC20 redemptionToken = new MockERC20("Dai Stablecoin", "DAI", 18);
        MockAsyncRedeemVault tokenToRedeem =
            new MockAsyncRedeemVault("Async Vault", "ASYNC", 18, redemptionToken, 2 ether);
        MockOracle oracle = new MockOracle(2e18);
        MigratablesFactory factory = new MigratablesFactory(address(this));
        TestBaseAsyncRedeemAccount implementation = new TestBaseAsyncRedeemAccount(
            address(oracle), address(factory), address(tokenToRedeem), address(redemptionToken), cowSwapSettlement
        );
        factory.whitelist(address(implementation));
        TestBaseAsyncRedeemAccount account = TestBaseAsyncRedeemAccount(
            factory.create(1, address(this), _initData(address(accountAsset), address(tokenToRedeem)))
        );

        assertEq(account.REDEMPTION_TOKEN(), address(redemptionToken));

        tokenToRedeem.mint(address(account), 1 ether);
        account.sync();
        tokenToRedeem.fulfill(0, address(account), 1 ether);

        assertEq(account.totalAssets(), 2e6);

        account.sync();

        assertEq(redemptionToken.balanceOf(address(account)), 2 ether);
        assertEq(accountAsset.balanceOf(address(account)), 0);
        assertEq(account.totalAssets(), 2e6);
    }

    function testAsyncRedeemAccountDoesNotExposeTotalRequests() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockAsyncRedeemVault tokenToRedeem = new MockAsyncRedeemVault("Centrifuge Share", "CFGSHARE", 18, asset, 2e6);
        MockOracle oracle = new MockOracle(2e18);
        TestAsyncRedeemAccount account = _deployAsyncRedeem(tokenToRedeem, asset, oracle);

        (bool success,) = address(account).staticcall(abi.encodeCall(ILegacyTotalRequests.totalRequests, ()));
        assertFalse(success);
    }

    function testAsyncRedeemAccountExposesCowSwapConverter() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockAsyncRedeemVault tokenToRedeem = new MockAsyncRedeemVault("Centrifuge Share", "CFGSHARE", 18, asset, 2e6);
        MockOracle oracle = new MockOracle(2e18);
        TestAsyncRedeemAccount account = _deployAsyncRedeem(tokenToRedeem, asset, oracle);

        (bool success, bytes memory returnData) =
            address(account).staticcall(abi.encodeCall(ICoWSwapConverter.COW_SWAP_SETTLEMENT, ()));
        assertTrue(success);
        assertEq(abi.decode(returnData, (address)), cowSwapSettlement);
    }

    function testAsyncRedeemAccountQuotesZeroWhenMockOracleReturnsZero() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockAsyncRedeemVault tokenToRedeem = new MockAsyncRedeemVault("Centrifuge Share", "CFGSHARE", 18, asset, 2e6);
        MockOracle oracle = new MockOracle(0);
        TestAsyncRedeemAccount account = _deployAsyncRedeem(tokenToRedeem, asset, oracle);

        tokenToRedeem.mint(address(account), 1 ether);

        assertEq(account.totalAssets(), 0);
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

    function testAsyncRedeemAccountClaimsAllRequestsWithMaxRedeem() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockAsyncRedeemVault tokenToRedeem = new MockAsyncRedeemVault("Centrifuge Share", "CFGSHARE", 18, asset, 2e6);
        MockOracle oracle = new MockOracle(2e18);
        TestAsyncRedeemAccount account = _deployAsyncRedeem(tokenToRedeem, asset, oracle);
        tokenToRedeem.setFreshRequestIds(true);

        tokenToRedeem.mint(address(account), 1 ether);
        account.sync();
        tokenToRedeem.mint(address(account), 2 ether);
        account.sync();

        tokenToRedeem.fulfill(0, address(account), 1 ether);
        tokenToRedeem.fulfill(1, address(account), 2 ether);

        account.sync();

        assertEq(tokenToRedeem.redeemCalls(address(account)), 1);
        assertEq(asset.balanceOf(address(account)), 6e6);
        assertEq(account.totalAssets(), 6e6);
        vm.expectRevert();
        account.requestIds(0);
    }

    function testAsyncRedeemAccountClaimsRedemptionThatBecomesClaimableAfterRequestIsRemoved() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockAsyncRedeemVault tokenToRedeem = new MockAsyncRedeemVault("Centrifuge Share", "CFGSHARE", 18, asset, 2e6);
        MockOracle oracle = new MockOracle(2e18);
        TestAsyncRedeemAccount account = _deployAsyncRedeem(tokenToRedeem, asset, oracle);

        tokenToRedeem.mint(address(account), 1 ether);
        account.sync();

        tokenToRedeem.process(0, address(account), 1 ether);
        account.sync();

        vm.expectRevert();
        account.requestIds(0);

        tokenToRedeem.makeClaimable(0, address(account), 1 ether);
        account.sync();

        assertEq(tokenToRedeem.redeemCalls(address(account)), 1);
        assertEq(asset.balanceOf(address(account)), 2e6);
    }

    function testAsyncRedeemAccountClaimsFulfilledRequestsAndKeepsPendingRemainder() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockAsyncRedeemVault tokenToRedeem = new MockAsyncRedeemVault("Centrifuge Share", "CFGSHARE", 18, asset, 2e6);
        MockOracle oracle = new MockOracle(2e18);
        TestAsyncRedeemAccount account = _deployAsyncRedeem(tokenToRedeem, asset, oracle);
        tokenToRedeem.setFreshRequestIds(true);

        tokenToRedeem.mint(address(account), 3 ether);
        account.sync();
        tokenToRedeem.mint(address(account), 2 ether);
        account.sync();

        tokenToRedeem.fulfill(0, address(account), 1 ether);
        tokenToRedeem.fulfill(1, address(account), 2 ether);
        tokenToRedeem.setAssetsPerShare(4e6);

        account.sync();

        assertEq(tokenToRedeem.redeemCalls(address(account)), 1);
        assertEq(asset.balanceOf(address(account)), 6e6);
        assertEq(account.requestIds(0), 0);
        vm.expectRevert();
        account.requestIds(1);
        assertEq(tokenToRedeem.pending(0, address(account)), 2 ether);
        assertEq(account.totalAssets(), 10e6);
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

        // Oracle and vault prices double after fulfillment.
        oracle.setPrice(4e18);
        tokenToRedeem.setAssetsPerShare(4e6);

        // Claimable stays frozen at 2e6 while the pending request follows the 4e18 oracle price.
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
            new JTRSY_Account(address(oracle), address(factory), address(1), cowSwapSettlement).TOKEN_TO_REDEEM(),
            JTRSY_TOKEN_ADDRESS
        );
        assertEq(
            new JAAA_Account(address(oracle), address(factory), address(1), cowSwapSettlement).TOKEN_TO_REDEEM(),
            JAAA_TOKEN_ADDRESS
        );
        assertEq(
            new ACRDX_Account(address(oracle), address(factory), address(1), cowSwapSettlement).TOKEN_TO_REDEEM(),
            ACRDX_TOKEN_ADDRESS
        );
        assertEq(
            new deCRDX_Account(address(oracle), address(factory), address(1), cowSwapSettlement).TOKEN_TO_REDEEM(),
            DECRDX_TOKEN_ADDRESS
        );
        assertEq(
            new deJTRSY_Account(address(oracle), address(factory), address(1), cowSwapSettlement).TOKEN_TO_REDEEM(),
            DEJTRSY_TOKEN_ADDRESS
        );
        assertEq(
            new deJAAA_Account(address(oracle), address(factory), address(1), cowSwapSettlement).TOKEN_TO_REDEEM(),
            DEJAAA_TOKEN_ADDRESS
        );

        assertEq(new JTRSY_Account(address(oracle), address(factory), address(1), cowSwapSettlement).COOLDOWN(), 1 days);
        assertEq(new JAAA_Account(address(oracle), address(factory), address(1), cowSwapSettlement).COOLDOWN(), 1 days);
        assertEq(new ACRDX_Account(address(oracle), address(factory), address(1), cowSwapSettlement).COOLDOWN(), 1 days);
        assertEq(
            new deCRDX_Account(address(oracle), address(factory), address(1), cowSwapSettlement).COOLDOWN(), 1 days
        );
        assertEq(
            new deJTRSY_Account(address(oracle), address(factory), address(1), cowSwapSettlement).COOLDOWN(), 1 days
        );
        assertEq(
            new deJAAA_Account(address(oracle), address(factory), address(1), cowSwapSettlement).COOLDOWN(), 1 days
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
            IAccount(
                    _centrifugeAccountAddress(
                        new JTRSY_Account(address(oracle), address(factory), address(1), cowSwapSettlement)
                    )
                ).TOKEN_TO_REDEEM(),
            JTRSY_TOKEN_ADDRESS
        );
        assertEq(
            IAccount(
                    _centrifugeAccountAddress(
                        new JAAA_Account(address(oracle), address(factory), address(1), cowSwapSettlement)
                    )
                ).TOKEN_TO_REDEEM(),
            JAAA_TOKEN_ADDRESS
        );
        assertEq(
            IAccount(
                    _centrifugeAccountAddress(
                        new ACRDX_Account(address(oracle), address(factory), address(1), cowSwapSettlement)
                    )
                ).TOKEN_TO_REDEEM(),
            ACRDX_TOKEN_ADDRESS
        );
        assertEq(
            IAccount(
                    _centrifugeAccountAddress(
                        new deCRDX_Account(address(oracle), address(factory), address(1), cowSwapSettlement)
                    )
                ).TOKEN_TO_REDEEM(),
            DECRDX_TOKEN_ADDRESS
        );
        assertEq(
            IAccount(
                    _centrifugeAccountAddress(
                        new deJTRSY_Account(address(oracle), address(factory), address(1), cowSwapSettlement)
                    )
                ).TOKEN_TO_REDEEM(),
            DEJTRSY_TOKEN_ADDRESS
        );
        assertEq(
            IAccount(
                    _centrifugeAccountAddress(
                        new deJAAA_Account(address(oracle), address(factory), address(1), cowSwapSettlement)
                    )
                ).TOKEN_TO_REDEEM(),
            DEJAAA_TOKEN_ADDRESS
        );
    }

    function _centrifugeAccountAddress(CentrifugeAccount account) internal pure returns (address) {
        return address(account);
    }
}

contract MockAsyncRedeemVaultWithoutDecimals {
    MockERC20 internal immutable _asset;
    MockERC20 internal immutable _tokenToRedeem;
    uint256 internal immutable _assetsPerShare;

    constructor(MockERC20 asset_, MockERC20 tokenToRedeem_, uint256 assetsPerShare_) {
        _asset = asset_;
        _tokenToRedeem = tokenToRedeem_;
        _assetsPerShare = assetsPerShare_;
    }

    function asset() external view returns (address) {
        return address(_asset);
    }

    function convertToAssets(uint256 shares) external view returns (uint256) {
        return shares * _assetsPerShare / 10 ** _tokenToRedeem.decimals();
    }
}
