// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {MidasCompAccount, MidasNonCompAccount} from "../../../src/contracts/adapters/ll-adapter/MidasAccount.sol";
import {ChainlinkOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/ChainlinkOracle.sol";
import {MidasOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/MidasOracle.sol";
import {mBTC_Account} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mBTC_Account.sol";
import {mHyperBTC_Account} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mHyperBTC_Account.sol";
import {mHyperETH_Account} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mHyperETH_Account.sol";
import {mRe7BTC_Account} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mRe7BTC_Account.sol";
import {mevBTC_Account} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mevBTC_Account.sol";
import {MigratablesFactory} from "../../../src/contracts/common/MigratablesFactory.sol";
import {IConverter} from "../../../src/interfaces/adapters/common/IConverter.sol";
import {ICoWSwapConverter} from "../../../src/interfaces/adapters/common/ICoWSwapConverter.sol";
import {IAccount} from "../../../src/interfaces/adapters/ll-adapter/IAccount.sol";
import {IOracle} from "../../../src/interfaces/adapters/ll-adapter/IOracle.sol";
import {
    IMidasAccount,
    REQUEST_STATUS_PENDING
} from "../../../src/interfaces/adapters/ll-adapter/midas/IMidasAccount.sol";
import {IChainlinkOracle} from "../../../src/interfaces/adapters/ll-adapter/oracles/IChainlinkOracle.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MidasAccountOraclesTest is Test {
    uint256 internal constant MAX_EXPECTED_REQUESTS = 17;

    address internal constant MAINNET_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address internal constant MBTC_TOKEN_ADDRESS = 0x007115416AB6c266329a03B09a8aa39aC2eF7d9d;
    address internal constant MBTC_REDEMPTION_VAULT_ADDRESS = 0x30d9D1e76869516AEa980390494AaEd45C3EfC1a;
    address internal constant MHYPERBTC_TOKEN_ADDRESS = 0xC8495EAFf71D3A563b906295fCF2f685b1783085;
    address internal constant MHYPERBTC_REDEMPTION_VAULT_ADDRESS = 0x16d4f955B0aA1b1570Fe3e9bB2f8c19C407cdb67;
    address internal constant MHYPERETH_TOKEN_ADDRESS = 0x5a42864b14C0C8241EF5ab62Dae975b163a2E0C1;
    address internal constant MHYPERETH_REDEMPTION_VAULT_ADDRESS = 0x15f724b35A75F0c28F352b952eA9D1b24e348c57;
    address internal constant MRE7BTC_TOKEN_ADDRESS = 0x9FB442d6B612a6dcD2acC67bb53771eF1D9F661A;
    address internal constant MRE7BTC_REDEMPTION_VAULT_ADDRESS = 0x4Fd4DD7171D14e5bD93025ec35374d2b9b4321b0;
    address internal constant MEVBTC_TOKEN_ADDRESS = 0xb64C014307622eB15046C66fF71D04258F5963DC;
    address internal constant MEVBTC_REDEMPTION_VAULT_ADDRESS = 0x2d7d5b1706653796602617350571B3F8999B950c;

    address internal adapter = makeAddr("adapter");
    address internal oracle = makeAddr("oracle");
    address internal vault = makeAddr("vault");
    address internal cowSettlement = makeAddr("cowSettlement");
    address internal cowRelayer = makeAddr("cowRelayer");

    function testMidasCompAccountPricesPendingRequestsAtCurrentRateUntilProcessed() public {
        MockERC20 tokenToRedeem = new MockERC20("Midas Token", "mTKN");
        MockERC20 asset = new MockERC20("Asset", "ASSET");
        MockMidasDataFeed mTokenDataFeed = new MockMidasDataFeed(1e18);
        MockMidasRedemptionVault redemptionVault =
            new MockMidasRedemptionVault(address(tokenToRedeem), address(mTokenDataFeed));
        redemptionVault.setDataFeed(address(asset), address(new MockMidasDataFeed(1e18)));
        MidasCompAccount account =
            _deployCompAccount(tokenToRedeem, asset, address(new MockERC20("Fallback", "FB")), redemptionVault);

        tokenToRedeem.mint(address(account), 100 ether);

        assertEq(account.ORACLE(), oracle);
        assertEq(account.vault(), vault);
        assertEq(account.converters(0), address(this));
        assertEq(account.totalAssets(), 100 ether);
        account.sync();

        mTokenDataFeed.setAnswer(2e18);

        assertEq(account.totalAssets(), 200 ether);

        redemptionVault.approveRequest(0, 2e18);

        account.sync();
        assertEq(asset.balanceOf(address(account)), 200 ether);
        assertEq(account.totalAssets(), 200 ether);
    }

    function testMidasNonCompAccountLocksPendingRequestValueAtCreationRate() public {
        MockERC20 tokenToRedeem = new MockERC20("Midas Token", "mTKN");
        MockERC20 asset = new MockERC20("Asset", "ASSET");
        MockMidasDataFeed mTokenDataFeed = new MockMidasDataFeed(1e18);
        MockMidasRedemptionVault redemptionVault =
            new MockMidasRedemptionVault(address(tokenToRedeem), address(mTokenDataFeed));
        redemptionVault.setDataFeed(address(asset), address(new MockMidasDataFeed(1e18)));
        MidasNonCompAccount account =
            _deployNonCompAccount(tokenToRedeem, asset, address(new MockERC20("Fallback", "FB")), redemptionVault);

        tokenToRedeem.mint(address(account), 100 ether);

        account.sync();

        mTokenDataFeed.setAnswer(2e18);

        assertEq(account.totalAssets(), 100 ether);

        redemptionVault.approveRequest(0, 2e18);

        account.sync();
        assertEq(asset.balanceOf(address(account)), 200 ether);
        assertEq(account.totalAssets(), 200 ether);
    }

    function testMidasAccountRealizesProceedsOnDeallocate() public {
        MockERC20 tokenToRedeem = new MockERC20("Midas Token", "mTKN");
        MockERC20 asset = new MockERC20("Asset", "ASSET");
        MockMidasDataFeed mTokenDataFeed = new MockMidasDataFeed(1e18);
        MockMidasRedemptionVault redemptionVault =
            new MockMidasRedemptionVault(address(tokenToRedeem), address(mTokenDataFeed));
        redemptionVault.setDataFeed(address(asset), address(new MockMidasDataFeed(1e18)));
        MidasCompAccount account =
            _deployCompAccount(tokenToRedeem, asset, address(new MockERC20("Fallback", "FB")), redemptionVault);

        tokenToRedeem.mint(address(account), 100 ether);
        account.sync();

        redemptionVault.approveRequest(0, 2e18);

        account.sync();

        assertEq(asset.balanceOf(address(account)), 200 ether);
        assertEq(asset.allowance(address(account), adapter), type(uint256).max);
    }

    function testMidasAccountHandlesCanceledRequestByReturningTokenToRedeem() public {
        MockERC20 tokenToRedeem = new MockERC20("Midas Token", "mTKN");
        MockERC20 asset = new MockERC20("Asset", "ASSET");
        MockMidasRedemptionVault redemptionVault =
            new MockMidasRedemptionVault(address(tokenToRedeem), address(new MockMidasDataFeed(1e18)));
        redemptionVault.setDataFeed(address(asset), address(new MockMidasDataFeed(1e18)));
        MidasCompAccount account =
            _deployCompAccount(tokenToRedeem, asset, address(new MockERC20("Fallback", "FB")), redemptionVault);

        tokenToRedeem.mint(address(account), 100 ether);
        account.sync();

        assertEq(account.totalAssets(), 100 ether);

        // Midas cancels the request and returns the token-to-redeem to the account.
        redemptionVault.cancelRequest(0);
        assertEq(tokenToRedeem.balanceOf(address(account)), 100 ether);

        // sync() prunes the canceled request and re-batches the returned token-to-redeem into a new request.
        account.sync();
        assertEq(asset.balanceOf(address(account)), 0);
        assertEq(tokenToRedeem.balanceOf(address(account)), 0);

        // No value lost or double-counted: the re-submitted request is valued back at 100.
        assertEq(account.totalAssets(), 100 ether);
    }

    function testMidasAccountRedeemsIntoConfiguredAsset() public {
        MockERC20 tokenToRedeem = new MockERC20("Midas Token", "mTKN");
        MockERC20 asset = new MockERC20("Asset", "ASSET");
        MockERC20 fallbackToken = new MockERC20("Fallback", "FB");
        MockMidasRedemptionVault redemptionVault =
            new MockMidasRedemptionVault(address(tokenToRedeem), address(new MockMidasDataFeed(1e18)));
        redemptionVault.setDataFeed(address(asset), address(new MockMidasDataFeed(1e18)));
        MidasNonCompAccount account =
            _deployNonCompAccount(tokenToRedeem, asset, address(fallbackToken), redemptionVault);
        tokenToRedeem.mint(address(account), 100 ether);

        account.sync();

        assertEq(redemptionVault.lastTokenOut(), address(asset));
        assertEq(redemptionVault.lastAmountMTokenIn(), 100 ether);
        assertEq(tokenToRedeem.balanceOf(address(redemptionVault)), 100 ether);
        assertEq(account.totalAssets(), 100 ether);
    }

    function testMidasAccountRedeemsIntoFallbackTokenWhenAssetIsUnsupported() public {
        MockERC20 tokenToRedeem = new MockERC20("Midas Token", "mTKN");
        MockERC20 asset = new MockERC20("Asset", "ASSET");
        MockERC20 fallbackToken = new MockERC20("Fallback", "FALLBACK");
        MockMidasRedemptionVault redemptionVault =
            new MockMidasRedemptionVault(address(tokenToRedeem), address(new MockMidasDataFeed(1e18)));
        redemptionVault.setDataFeed(address(fallbackToken), address(new MockMidasDataFeed(1e18)));
        MidasNonCompAccount account =
            _deployNonCompAccount(tokenToRedeem, asset, address(fallbackToken), redemptionVault);
        tokenToRedeem.mint(address(account), 100 ether);

        account.sync();

        assertEq(redemptionVault.lastTokenOut(), address(fallbackToken));
        assertEq(redemptionVault.lastAmountMTokenIn(), 100 ether);
    }

    function testMidasAccountNormalizesHeldFallbackTokenToAssetDecimals() public {
        MockERC20 tokenToRedeem = new MockERC20("Midas Token", "mTKN");
        MockERC20 asset = new MockERC20("Asset", "ASSET");
        MockERC20Decimals fallbackToken = new MockERC20Decimals("Fallback", "FALLBACK", 6);
        MockMidasRedemptionVault redemptionVault =
            new MockMidasRedemptionVault(address(tokenToRedeem), address(new MockMidasDataFeed(1e18)));
        MidasNonCompAccount account =
            _deployNonCompAccount(tokenToRedeem, asset, address(fallbackToken), redemptionVault);

        fallbackToken.mint(address(account), 100e6);

        assertEq(account.totalAssets(), 100 ether);
    }

    function testMidasAccountRedeemDoesNothingWithNoBalance() public {
        MockERC20 tokenToRedeem = new MockERC20("Midas Token", "mTKN");
        MockERC20 asset = new MockERC20("Asset", "ASSET");
        MockMidasRedemptionVault redemptionVault =
            new MockMidasRedemptionVault(address(tokenToRedeem), address(new MockMidasDataFeed(1e18)));
        MidasNonCompAccount account =
            _deployNonCompAccount(tokenToRedeem, asset, address(new MockERC20("Fallback", "FB")), redemptionVault);

        account.sync();
        assertEq(redemptionVault.lastTokenOut(), address(0));
    }

    function testMidasAccountSkipsTokenToRedeemOracleWhenBalanceIsZero() public {
        MockERC20 tokenToRedeem = new MockERC20("Midas Token", "mTKN");
        MockERC20 asset = new MockERC20("Asset", "ASSET");
        MockMidasRedemptionVault redemptionVault =
            new MockMidasRedemptionVault(address(tokenToRedeem), address(new MockMidasDataFeed(0)));
        MidasNonCompAccount account =
            _deployNonCompAccount(tokenToRedeem, asset, address(new MockERC20("Fallback", "FB")), redemptionVault);

        assertEq(account.totalAssets(), 0);
    }

    function testMidasCompAccountSkipsPendingOracleWhenNoRequests() public {
        MockERC20 tokenToRedeem = new MockERC20("Midas Token", "mTKN");
        MockERC20 asset = new MockERC20("Asset", "ASSET");
        MockMidasRedemptionVault redemptionVault =
            new MockMidasRedemptionVault(address(tokenToRedeem), address(new MockMidasDataFeed(0)));
        MidasCompAccount account =
            _deployCompAccount(tokenToRedeem, asset, address(new MockERC20("Fallback", "FB")), redemptionVault);

        assertEq(account.totalAssets(), 0);
    }

    function testMidasCompAccountSkipsOracleWhenOnlyZeroAmountIsPending() public {
        MockERC20 tokenToRedeem = new MockERC20("Midas Token", "mTKN");
        MockERC20 asset = new MockERC20("Asset", "ASSET");
        MockMidasRedemptionVault redemptionVault =
            new MockMidasRedemptionVault(address(tokenToRedeem), address(new MockMidasDataFeed(0)));
        TestMidasCompAccount account =
            _deployTestCompAccount(tokenToRedeem, asset, address(new MockERC20("Fallback", "FB")), redemptionVault);

        redemptionVault.setRequest(0, address(account), address(asset), REQUEST_STATUS_PENDING, 0, 0, 1e18);
        account.pushRequestId(0);

        assertEq(account.totalAssets(), 0);
    }

    function testAccountTokenToRedeemToAssetsSkipsOracleForZeroAmount() public {
        MockERC20 tokenToRedeem = new MockERC20("Midas Token", "mTKN");
        MockERC20 asset = new MockERC20("Asset", "ASSET");
        MockMidasRedemptionVault redemptionVault =
            new MockMidasRedemptionVault(address(tokenToRedeem), address(new MockMidasDataFeed(0)));
        TestMidasCompAccount account =
            _deployTestCompAccount(tokenToRedeem, asset, address(new MockERC20("Fallback", "FB")), redemptionVault);

        assertEq(account.exposedTokenToRedeemToAssets(0), 0);
    }

    function testAccountTokenToRedeemToAssetsWithRateSkipsRateMathForZeroAmount() public {
        MockERC20 tokenToRedeem = new MockERC20("Midas Token", "mTKN");
        MockERC20 asset = new MockERC20("Asset", "ASSET");
        MockMidasRedemptionVault redemptionVault =
            new MockMidasRedemptionVault(address(tokenToRedeem), address(new MockMidasDataFeed(1e18)));
        TestMidasCompAccount account =
            _deployTestCompAccount(tokenToRedeem, asset, address(new MockERC20("Fallback", "FB")), redemptionVault);

        assertEq(account.exposedTokenToRedeemToAssets(0, type(uint256).max), 0);
    }

    function testMidasAccountDoesNotExposeRequestRedeem() public {
        MockERC20 tokenToRedeem = new MockERC20("Midas Token", "mTKN");
        MockERC20 asset = new MockERC20("Asset", "ASSET");
        MockMidasRedemptionVault redemptionVault =
            new MockMidasRedemptionVault(address(tokenToRedeem), address(new MockMidasDataFeed(1e18)));
        MidasNonCompAccount account =
            _deployNonCompAccount(tokenToRedeem, asset, address(new MockERC20("Fallback", "FB")), redemptionVault);

        (bool success,) = address(account).call(abi.encodeWithSignature("requestRedeem()"));
        assertFalse(success);
    }

    function testMidasAccountDoesNotExposeTotalRequests() public {
        MockERC20 tokenToRedeem = new MockERC20("Midas Token", "mTKN");
        MockERC20 asset = new MockERC20("Asset", "ASSET");
        MockMidasRedemptionVault redemptionVault =
            new MockMidasRedemptionVault(address(tokenToRedeem), address(new MockMidasDataFeed(1e18)));
        MidasNonCompAccount account =
            _deployNonCompAccount(tokenToRedeem, asset, address(new MockERC20("Fallback", "FB")), redemptionVault);

        (bool success,) = address(account).staticcall(abi.encodeWithSignature("totalRequests()"));
        assertFalse(success);
    }

    function testMidasAccountDoesNotCapPendingRequests() public {
        MockERC20 tokenToRedeem = new MockERC20("Midas Token", "mTKN");
        MockERC20 asset = new MockERC20("Asset", "ASSET");
        MockMidasRedemptionVault redemptionVault =
            new MockMidasRedemptionVault(address(tokenToRedeem), address(new MockMidasDataFeed(1e18)));
        redemptionVault.setDataFeed(address(asset), address(new MockMidasDataFeed(1e18)));
        MidasNonCompAccount account =
            _deployNonCompAccount(tokenToRedeem, asset, address(new MockERC20("Fallback", "FB")), redemptionVault);

        for (uint256 i; i < 25; ++i) {
            tokenToRedeem.mint(address(account), 1 ether);
            account.sync();
        }

        assertEq(redemptionVault.currentRequestId(), 25);
        assertEq(tokenToRedeem.balanceOf(address(account)), 0);
        assertEq(account.totalAssets(), 25 ether);
    }

    function testBenchmarkMidasRequestIdsMaxExpectedRequests() public {
        MockERC20 tokenToRedeem = new MockERC20("Midas Token", "mTKN");
        MockERC20 asset = new MockERC20("Asset", "ASSET");
        MockMidasRedemptionVault redemptionVault =
            new MockMidasRedemptionVault(address(tokenToRedeem), address(new MockMidasDataFeed(1e18)));
        redemptionVault.setDataFeed(address(asset), address(new MockMidasDataFeed(1e18)));
        MidasNonCompAccount account =
            _deployNonCompAccount(tokenToRedeem, asset, address(new MockERC20("Fallback", "FB")), redemptionVault);

        for (uint256 i; i < MAX_EXPECTED_REQUESTS - 1; ++i) {
            tokenToRedeem.mint(address(account), 1 ether);
            account.sync();
        }

        tokenToRedeem.mint(address(account), 1 ether);
        uint256 gasBefore = gasleft();
        account.sync();
        uint256 requestGas = gasBefore - gasleft();

        gasBefore = gasleft();
        uint256 assets = account.totalAssets();
        uint256 totalAssetsGas = gasBefore - gasleft();

        for (uint256 i; i < MAX_EXPECTED_REQUESTS; ++i) {
            redemptionVault.approveRequest(i, 1e18);
        }

        gasBefore = gasleft();
        account.sync();
        uint256 finalizeGas = gasBefore - gasleft();

        assertEq(assets, MAX_EXPECTED_REQUESTS * 1 ether);
        assertEq(asset.balanceOf(address(account)), MAX_EXPECTED_REQUESTS * 1 ether);

        emit log_named_uint("maxExpectedRequests", MAX_EXPECTED_REQUESTS);
        emit log_named_uint("requestGas", requestGas);
        emit log_named_uint("totalAssetsGas", totalAssetsGas);
        emit log_named_uint("finalizeGas", finalizeGas);
    }

    function testMidasAccountOwnerSyncBypassesCooldown() public {
        MockERC20 tokenToRedeem = new MockERC20("Midas Token", "mTKN");
        MockERC20 asset = new MockERC20("Asset", "ASSET");
        MockMidasRedemptionVault redemptionVault =
            new MockMidasRedemptionVault(address(tokenToRedeem), address(new MockMidasDataFeed(1e18)));
        redemptionVault.setDataFeed(address(asset), address(new MockMidasDataFeed(1e18)));
        MidasNonCompAccount account = _deployNonCompAccount(
            tokenToRedeem, asset, address(new MockERC20("Fallback", "FB")), redemptionVault, 1 days
        );

        tokenToRedeem.mint(address(account), 1 ether);
        account.sync();

        tokenToRedeem.mint(address(account), 1 ether);
        account.sync();

        assertEq(redemptionVault.currentRequestId(), 2);
        assertEq(tokenToRedeem.balanceOf(address(account)), 0);
    }

    function testMidasAccountPermissionlessSyncRespectsCooldown() public {
        MockERC20 tokenToRedeem = new MockERC20("Midas Token", "mTKN");
        MockERC20 asset = new MockERC20("Asset", "ASSET");
        MockMidasRedemptionVault redemptionVault =
            new MockMidasRedemptionVault(address(tokenToRedeem), address(new MockMidasDataFeed(1e18)));
        redemptionVault.setDataFeed(address(asset), address(new MockMidasDataFeed(1e18)));
        MidasNonCompAccount account = _deployNonCompAccount(
            tokenToRedeem, asset, address(new MockERC20("Fallback", "FB")), redemptionVault, 1 days
        );

        tokenToRedeem.mint(address(account), 1 ether);
        vm.prank(makeAddr("keeper"));
        account.sync();

        tokenToRedeem.mint(address(account), 1 ether);
        vm.prank(makeAddr("keeper"));
        account.sync();

        assertEq(redemptionVault.currentRequestId(), 1);
        assertEq(tokenToRedeem.balanceOf(address(account)), 1 ether);

        vm.warp(vm.getBlockTimestamp() + 1 days);
        vm.prank(makeAddr("keeper"));
        account.sync();

        assertEq(redemptionVault.currentRequestId(), 2);
        assertEq(tokenToRedeem.balanceOf(address(account)), 0);
    }

    function testMidasBtcEthTokenAccountsAcceptOnlyCorrelatedVaultAsset() public {
        _assertMidasBtcEthTokenAccountAcceptsOnlyCorrelatedVaultAsset(
            0, MBTC_TOKEN_ADDRESS, MBTC_REDEMPTION_VAULT_ADDRESS, WBTC, 8
        );
        _assertMidasBtcEthTokenAccountAcceptsOnlyCorrelatedVaultAsset(
            1, MHYPERBTC_TOKEN_ADDRESS, MHYPERBTC_REDEMPTION_VAULT_ADDRESS, WBTC, 8
        );
        _assertMidasBtcEthTokenAccountAcceptsOnlyCorrelatedVaultAsset(
            2, MHYPERETH_TOKEN_ADDRESS, MHYPERETH_REDEMPTION_VAULT_ADDRESS, WETH, 18
        );
        _assertMidasBtcEthTokenAccountAcceptsOnlyCorrelatedVaultAsset(
            3, MRE7BTC_TOKEN_ADDRESS, MRE7BTC_REDEMPTION_VAULT_ADDRESS, WBTC, 8
        );
        _assertMidasBtcEthTokenAccountAcceptsOnlyCorrelatedVaultAsset(
            4, MEVBTC_TOKEN_ADDRESS, MEVBTC_REDEMPTION_VAULT_ADDRESS, WBTC, 8
        );
    }

    function testConvertRejectsNonAssetTokenOut() public {
        MockERC20 tokenToRedeem = new MockERC20("Midas Token", "mTKN");
        MockERC20 asset = new MockERC20("Asset", "ASSET");
        MockMidasRedemptionVault redemptionVault =
            new MockMidasRedemptionVault(address(tokenToRedeem), address(new MockMidasDataFeed(1e18)));
        MidasNonCompAccount account =
            _deployNonCompAccount(tokenToRedeem, asset, address(new MockERC20("Fallback", "FB")), redemptionVault);

        vm.expectRevert(IConverter.InvalidTokenOut.selector);
        account.convert(makeAddr("redemptionToken"), 1 ether, makeAddr("notAsset"), "");
    }

    function testConvertRejectsAssetTokenIn() public {
        MockERC20 tokenToRedeem = new MockERC20("Midas Token", "mTKN");
        MockERC20 asset = new MockERC20("Asset", "ASSET");
        MockMidasRedemptionVault redemptionVault =
            new MockMidasRedemptionVault(address(tokenToRedeem), address(new MockMidasDataFeed(1e18)));
        MidasNonCompAccount account =
            _deployNonCompAccount(tokenToRedeem, asset, address(new MockERC20("Fallback", "FB")), redemptionVault);

        vm.expectRevert(ICoWSwapConverter.InvalidTokenIn.selector);
        account.convert(address(asset), 1 ether, address(asset), "");
    }

    function testConvertRejectsTokenToRedeemTokenIn() public {
        MockERC20 tokenToRedeem = new MockERC20("Midas Token", "mTKN");
        MockERC20 asset = new MockERC20("Asset", "ASSET");
        MockMidasRedemptionVault redemptionVault =
            new MockMidasRedemptionVault(address(tokenToRedeem), address(new MockMidasDataFeed(1e18)));
        MidasNonCompAccount account =
            _deployNonCompAccount(tokenToRedeem, asset, address(new MockERC20("Fallback", "FB")), redemptionVault);

        vm.expectRevert(ICoWSwapConverter.InvalidTokenIn.selector);
        account.convert(address(tokenToRedeem), 1 ether, address(asset), "");
    }

    function testChainlinkOracleReturnsLatestPriceInBase18() public {
        MockChainlinkAggregator aggregator = new MockChainlinkAggregator(8);
        aggregator.setLatestRoundData(1, 123e8, uint48(vm.getBlockTimestamp()), 1);
        ChainlinkOracle oracle =
            new ChainlinkOracle(1, type(uint256).max, [address(aggregator), address(0)], [uint48(1 days), uint48(0)]);

        assertEq(oracle.getPrice(), 123e18);
    }

    function testChainlinkOracleMultipliesSecondAggregatorHop() public {
        MockChainlinkAggregator aggregator0 = new MockChainlinkAggregator(8);
        MockChainlinkAggregator aggregator1 = new MockChainlinkAggregator(18);
        aggregator0.setLatestRoundData(1, 2e8, uint48(vm.getBlockTimestamp()), 1);
        aggregator1.setLatestRoundData(1, 3e18, uint48(vm.getBlockTimestamp()), 1);
        ChainlinkOracle oracle = new ChainlinkOracle(
            1, type(uint256).max, [address(aggregator0), address(aggregator1)], [uint48(1 days), uint48(1 days)]
        );

        assertEq(oracle.getPrice(), 6e18);
    }

    function testChainlinkOracleRevertsForStalePrice() public {
        vm.warp(10 days);
        MockChainlinkAggregator aggregator = new MockChainlinkAggregator(8);
        aggregator.setLatestRoundData(1, 123e8, uint48(vm.getBlockTimestamp() - 2 days), 1);
        ChainlinkOracle oracle =
            new ChainlinkOracle(1, type(uint256).max, [address(aggregator), address(0)], [uint48(1 days), uint48(0)]);

        vm.expectRevert(IOracle.InvalidPrice.selector);
        oracle.getPrice();
    }

    function testChainlinkOracleRevertsWithNoFirstAggregator() public {
        vm.expectRevert(IChainlinkOracle.InvalidAggregator.selector);
        new ChainlinkOracle(1, type(uint256).max, [address(0), makeAddr("aggregator")], [uint48(1 days), uint48(0)]);
    }

    function testMidasOracleReturnsFeedPrice() public {
        MockMidasDataFeed dataFeed = new MockMidasDataFeed(42e18);
        MidasOracle oracle = new MidasOracle(1, type(uint256).max, address(dataFeed));

        assertEq(oracle.getPrice(), 42e18);
    }

    function _deployCompAccount(
        MockERC20 tokenToRedeem,
        MockERC20 asset,
        address fallbackToken,
        MockMidasRedemptionVault redemptionVault
    ) internal returns (MidasCompAccount account) {
        vault = address(new MockVault(address(asset)));
        oracle = address(new MidasOracle(1, type(uint256).max, redemptionVault.mTokenDataFeed()));
        MigratablesFactory factory = new MigratablesFactory(address(this));
        vm.mockCall(cowSettlement, abi.encodeWithSignature("vaultRelayer()"), abi.encode(cowRelayer));
        MidasCompAccount implementation = new MidasCompAccount(
            oracle, address(factory), 0, address(tokenToRedeem), fallbackToken, address(redemptionVault), cowSettlement
        );
        factory.whitelist(address(implementation));
        account = MidasCompAccount(factory.create(1, address(this), _initData(address(tokenToRedeem))));
    }

    function _deployTestCompAccount(
        MockERC20 tokenToRedeem,
        MockERC20 asset,
        address fallbackToken,
        MockMidasRedemptionVault redemptionVault
    ) internal returns (TestMidasCompAccount account) {
        vault = address(new MockVault(address(asset)));
        oracle = address(new MidasOracle(1, type(uint256).max, redemptionVault.mTokenDataFeed()));
        MigratablesFactory factory = new MigratablesFactory(address(this));
        vm.mockCall(cowSettlement, abi.encodeWithSignature("vaultRelayer()"), abi.encode(cowRelayer));
        TestMidasCompAccount implementation = new TestMidasCompAccount(
            oracle, address(factory), 0, address(tokenToRedeem), fallbackToken, address(redemptionVault), cowSettlement
        );
        factory.whitelist(address(implementation));
        account = TestMidasCompAccount(factory.create(1, address(this), _initData(address(tokenToRedeem))));
    }

    function _deployNonCompAccount(
        MockERC20 tokenToRedeem,
        MockERC20 asset,
        address fallbackToken,
        MockMidasRedemptionVault redemptionVault
    ) internal returns (MidasNonCompAccount account) {
        account = _deployNonCompAccount(tokenToRedeem, asset, fallbackToken, redemptionVault, 0);
    }

    function _deployNonCompAccount(
        MockERC20 tokenToRedeem,
        MockERC20 asset,
        address fallbackToken,
        MockMidasRedemptionVault redemptionVault,
        uint48 cooldown
    ) internal returns (MidasNonCompAccount account) {
        vault = address(new MockVault(address(asset)));
        oracle = address(new MidasOracle(1, type(uint256).max, redemptionVault.mTokenDataFeed()));
        MigratablesFactory factory = new MigratablesFactory(address(this));
        vm.mockCall(cowSettlement, abi.encodeWithSignature("vaultRelayer()"), abi.encode(cowRelayer));
        MidasNonCompAccount implementation = new MidasNonCompAccount(
            oracle,
            address(factory),
            cooldown,
            address(tokenToRedeem),
            fallbackToken,
            address(redemptionVault),
            cowSettlement
        );
        factory.whitelist(address(implementation));
        account = MidasNonCompAccount(factory.create(1, address(this), _initData(address(tokenToRedeem))));
    }

    function _assertMidasBtcEthTokenAccountAcceptsOnlyCorrelatedVaultAsset(
        uint256 index,
        address tokenToRedeem,
        address redemptionVault,
        address correlatedAsset,
        uint8 correlatedAssetDecimals
    ) internal {
        MigratablesFactory factory = new MigratablesFactory(address(this));
        _mockMidasTokenAccountConstructor(tokenToRedeem, redemptionVault);
        _mockAsset(correlatedAsset, correlatedAssetDecimals);
        _mockAsset(MAINNET_USDC, 6);
        IAccount implementation = _deployMidasBtcEthTokenAccountImplementation(index, address(factory));
        factory.whitelist(address(implementation));

        vault = address(new MockVault(correlatedAsset));
        IAccount account = IAccount(factory.create(1, address(this), _initData(tokenToRedeem)));
        assertEq(account.vault(), vault);

        vault = address(new MockVault(MAINNET_USDC));
        vm.expectRevert(IMidasAccount.InvalidAsset.selector);
        factory.create(1, address(this), _initData(tokenToRedeem));
    }

    function _deployMidasBtcEthTokenAccountImplementation(uint256 index, address factory)
        internal
        returns (IAccount implementation)
    {
        if (index == 0) {
            return IAccount(address(new mBTC_Account(factory, cowSettlement)));
        }
        if (index == 1) {
            return IAccount(address(new mHyperBTC_Account(factory, cowSettlement)));
        }
        if (index == 2) {
            return IAccount(address(new mHyperETH_Account(factory, cowSettlement)));
        }
        if (index == 3) {
            return IAccount(address(new mRe7BTC_Account(factory, cowSettlement)));
        }
        return IAccount(address(new mevBTC_Account(factory, cowSettlement)));
    }

    function _mockMidasTokenAccountConstructor(address tokenToRedeem, address redemptionVault) internal {
        vm.mockCall(cowSettlement, abi.encodeWithSignature("vaultRelayer()"), abi.encode(cowRelayer));
        vm.mockCall(tokenToRedeem, abi.encodeWithSignature("decimals()"), abi.encode(uint8(18)));
        vm.mockCall(
            redemptionVault,
            abi.encodeWithSignature("mTokenDataFeed()"),
            abi.encode(address(new MockMidasDataFeed(1e18)))
        );
    }

    function _mockAsset(address asset, uint8 decimals_) internal {
        vm.mockCall(asset, abi.encodeWithSignature("decimals()"), abi.encode(decimals_));
        vm.mockCall(
            asset, abi.encodeWithSelector(IERC20.approve.selector, adapter, type(uint256).max), abi.encode(true)
        );
    }

    function _initData(address) internal view returns (bytes memory) {
        return abi.encode(vault, adapter);
    }
}

contract TestMidasCompAccount is MidasCompAccount {
    constructor(
        address oracle,
        address factory,
        uint48 cooldown,
        address tokenToRedeem,
        address redemptionToken,
        address redemptionVault,
        address cowSwapSettlement
    ) MidasCompAccount(oracle, factory, cooldown, tokenToRedeem, redemptionToken, redemptionVault, cowSwapSettlement) {}

    function pushRequestId(uint64 requestId) public {
        requestIds.push(requestId);
    }

    function exposedTokenToRedeemToAssets(uint256 amount) public view returns (uint256) {
        return _tokenToRedeemToAssets(amount);
    }

    function exposedTokenToRedeemToAssets(uint256 amount, uint256 rate) public view returns (uint256) {
        return _tokenToRedeemToAssets(amount, rate);
    }
}

contract MockVault {
    address public asset;

    constructor(address asset_) {
        asset = asset_;
    }
}

contract MockERC20 is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address account, uint256 value) public {
        _mint(account, value);
    }
}

contract MockERC20Decimals is MockERC20 {
    uint8 internal immutable _decimals;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) MockERC20(name_, symbol_) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}

contract MockMidasRedemptionVault {
    uint8 internal constant PENDING = 0;
    uint8 internal constant PROCESSED = 1;
    uint8 internal constant CANCELED = 2;

    struct Request {
        address sender;
        address tokenOut;
        uint8 status;
        uint256 amountMToken;
        uint256 mTokenRate;
        uint256 tokenOutRate;
    }

    address public immutable tokenToRedeem;
    address public immutable mTokenDataFeed;
    address public lastTokenOut;
    uint256 public lastAmountMTokenIn;
    uint256 public currentRequestId;

    mapping(address token => address dataFeed) public dataFeedOf;
    mapping(address token => bool stable) public stableOf;
    mapping(uint256 requestId => Request request) public requests;

    constructor(address tokenToRedeem_, address mTokenDataFeed_) {
        tokenToRedeem = tokenToRedeem_;
        mTokenDataFeed = mTokenDataFeed_;
    }

    function setDataFeed(address token, address dataFeed) public {
        dataFeedOf[token] = dataFeed;
    }

    function setRequest(
        uint256 requestId,
        address sender,
        address tokenOut,
        uint8 status,
        uint256 amountMToken,
        uint256 mTokenRate,
        uint256 tokenOutRate
    ) public {
        requests[requestId] = Request({
            sender: sender,
            tokenOut: tokenOut,
            status: status,
            amountMToken: amountMToken,
            mTokenRate: mTokenRate,
            tokenOutRate: tokenOutRate
        });
    }

    function tokensConfig(address token)
        public
        view
        returns (address dataFeed, uint256 fee, uint256 allowance, bool stable)
    {
        dataFeed = dataFeedOf[token];
        stable = stableOf[token];
    }

    function redeemRequest(address tokenOut, uint256 amountMTokenIn) public returns (uint256 requestId) {
        lastTokenOut = tokenOut;
        lastAmountMTokenIn = amountMTokenIn;
        IERC20(tokenToRedeem).transferFrom(msg.sender, address(this), amountMTokenIn);
        requestId = currentRequestId++;
        requests[requestId] = Request({
            sender: msg.sender,
            tokenOut: tokenOut,
            status: PENDING,
            amountMToken: amountMTokenIn,
            mTokenRate: MockMidasDataFeed(mTokenDataFeed).getDataInBase18(),
            tokenOutRate: _tokenRate(tokenOut)
        });
    }

    function approveRequest(uint256 requestId, uint256 newMTokenRate) public {
        Request storage request = requests[requestId];
        request.status = PROCESSED;
        request.mTokenRate = newMTokenRate;
        MockERC20(request.tokenOut).mint(request.sender, request.amountMToken * newMTokenRate / request.tokenOutRate);
    }

    function cancelRequest(uint256 requestId) public {
        Request storage request = requests[requestId];
        request.status = CANCELED;
        IERC20(tokenToRedeem).transfer(request.sender, request.amountMToken);
    }

    function redeemRequests(uint256 requestId)
        public
        view
        returns (
            address sender,
            address tokenOut,
            uint8 status,
            uint256 amountMToken,
            uint256 mTokenRate,
            uint256 tokenOutRate
        )
    {
        Request storage request = requests[requestId];
        return (
            request.sender,
            request.tokenOut,
            request.status,
            request.amountMToken,
            request.mTokenRate,
            request.tokenOutRate
        );
    }

    function _tokenRate(address token) internal view returns (uint256) {
        if (stableOf[token]) {
            return 1e18;
        }
        return MockMidasDataFeed(dataFeedOf[token]).getDataInBase18();
    }
}

contract MockChainlinkAggregator {
    uint8 public immutable decimals;
    string public constant description = "Mock";
    uint256 public constant version = 1;

    uint80 internal _roundId;
    int256 internal _answer;
    uint48 internal _updatedAt;
    uint80 internal _answeredInRound;

    constructor(uint8 decimals_) {
        decimals = decimals_;
    }

    function setLatestRoundData(uint80 roundId, int256 answer, uint48 updatedAt, uint80 answeredInRound) public {
        _roundId = roundId;
        _answer = answer;
        _updatedAt = updatedAt;
        _answeredInRound = answeredInRound;
    }

    function getRoundData(uint80 roundId)
        public
        view
        returns (uint80, int256 answer, uint48 startedAt, uint48 updatedAt, uint80 answeredInRound)
    {
        if (roundId != _roundId) {
            revert("missing round");
        }
        return (roundId, _answer, _updatedAt, _updatedAt, _answeredInRound);
    }

    function latestRoundData()
        public
        view
        returns (uint80 roundId, int256 answer, uint48 startedAt, uint48 updatedAt, uint80 answeredInRound)
    {
        return (_roundId, _answer, _updatedAt, _updatedAt, _answeredInRound);
    }
}

contract MockMidasDataFeed {
    uint256 public answer;

    constructor(uint256 answer_) {
        answer = answer_;
    }

    function getDataInBase18() public view returns (uint256) {
        return answer;
    }

    function setAnswer(uint256 answer_) public {
        answer = answer_;
    }
}
