// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";

import {ACRED_Account} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/ACRED_Account.sol";
import {ACRDX_Account} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/ACRDX_Account.sol";
import {CentrifugeAccount} from "../../../src/contracts/adapters/ll-adapter/CentrifugeAccount.sol";
import {DigiFTAccount} from "../../../src/contracts/adapters/ll-adapter/DigiFTAccount.sol";
import {HumaAccount} from "../../../src/contracts/adapters/ll-adapter/HumaAccount.sol";
import {PikuAccount} from "../../../src/contracts/adapters/ll-adapter/PikuAccount.sol";
import {PikuFundingManagerAccount} from "../../../src/contracts/adapters/ll-adapter/PikuFundingManagerAccount.sol";
import {PRIME_Account} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/PRIME_Account.sol";
import {PST_Account} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/PST_Account.sol";
import {deJAAA_Account} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/deJAAA_Account.sol";
import {deJTRSY_Account} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/deJTRSY_Account.sol";
import {JAAA_Account} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/JAAA_Account.sol";
import {JTRSY_Account} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/JTRSY_Account.sol";
import {sUSD3_Account} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/sUSD3_Account.sol";
import {TheoAccount} from "../../../src/contracts/adapters/ll-adapter/TheoAccount.sol";
import {ThreeJaneAccount} from "../../../src/contracts/adapters/ll-adapter/ThreeJaneAccount.sol";
import {USP_Account} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/USP_Account.sol";
import {weETH_Account} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/weETH_Account.sol";
import {wstETH_Account} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/wstETH_Account.sol";
import {ChainlinkOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/ChainlinkOracle.sol";
import {MigratablesFactory} from "../../../src/contracts/common/MigratablesFactory.sol";
import {IAccount} from "../../../src/interfaces/adapters/ll-adapter/IAccount.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AccountsTest is Test {
    address internal constant ACRDX_TOKEN_ADDRESS = 0x9477724Bb54AD5417de8Baff29e59DF3fB4DA74f;
    address internal constant DEJAAA_TOKEN_ADDRESS = 0xAAA0008C8CF3A7Dca931adaF04336A5D808C82Cc;
    address internal constant DEJTRSY_TOKEN_ADDRESS = 0xA6233014B9b7aaa74f38fa1977ffC7A89642dC72;
    address internal constant JAAA_TOKEN_ADDRESS = 0x5a0F93D040De44e78F251b03c43be9CF317Dcf64;
    address internal constant JTRSY_TOKEN_ADDRESS = 0x8c213ee79581Ff4984583C6a801e5263418C4b86;
    address internal constant PST_TOKEN_ADDRESS = 0x22aE3D9a738471f405169Af055d31c687087d4c7;
    address internal constant PST_CHAINLINK_FEED_ADDRESS = 0x4BE50bE32dB1510240d542f77c5B36Ca0D0965E6;
    address internal constant SUSD3_TOKEN_ADDRESS = 0xf689555121e529Ff0463e191F9Bd9d1E496164a7;
    address internal constant USP_FUNDING_MANAGER_ADDRESS = 0x7e0305B212dF3FB56366251C054c07748Bf9a797;
    address internal constant USP_TOKEN_ADDRESS = 0x098697bA3Fee4eA76294C5d6A466a4e3b3E95FE6;
    uint48 internal constant PST_STALENESS_DURATION = 2 days;

    address internal adapter = makeAddr("adapter");
    address internal redemptionWallet = makeAddr("redemptionWallet");

    function testSecuritizeAccountForwardsHeldInventoryToRedemptionWallet() public {
        MockERC20 tokenToRedeem = new MockERC20("ACRED", "ACRED", 6);
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockOracle oracle = new MockOracle(2e18);
        ACRED_Account account = _deployACRED(tokenToRedeem, asset, oracle);

        tokenToRedeem.mint(address(account), 10e6);

        assertEq(account.ORACLE(), address(oracle));
        assertEq(MockVault(account.vault()).asset(), address(asset));
        assertEq(account.REDEMPTION_WALLET(), redemptionWallet);
        assertEq(account.totalAssets(), 20e6);

        account.sync();

        assertEq(tokenToRedeem.balanceOf(address(account)), 0);
        assertEq(tokenToRedeem.balanceOf(redemptionWallet), 10e6);
        assertEq(account.totalAssets(), 0);
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
            address(factory),
            address(oracle),
            address(wstETH),
            address(stETH),
            address(new MockLidoWithdrawalQueue(address(wstETH), address(stETH)))
        );
        factory.whitelist(address(implementation));

        wstETH_Account account =
            wstETH_Account(payable(factory.create(1, address(this), _initData(address(weth), address(wstETH)))));

        assertEq(MockVault(account.vault()).asset(), address(weth));
        assertEq(account.totalAssets(), 0);
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

        (bool success,) = address(account).staticcall(abi.encodeWithSignature("totalRequests()"));
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

    function testWeETHAccountInitializesWithoutLocalVaultAssetGuard() public {
        LstMocks memory mocks = _lstMocks();
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockOracle oracle = new MockOracle(1e18);
        MigratablesFactory factory = new MigratablesFactory(address(this));
        weETH_Account implementation = new weETH_Account(
            address(factory),
            address(oracle),
            address(mocks.weETH),
            address(mocks.eETH),
            address(mocks.liquidityPool),
            address(mocks.redemptionManager),
            address(mocks.withdrawRequestNft),
            address(mocks.weth)
        );
        factory.whitelist(address(implementation));

        weETH_Account account =
            weETH_Account(payable(factory.create(1, address(this), _initData(address(asset), address(mocks.weETH)))));

        assertEq(MockVault(account.vault()).asset(), address(asset));
    }

    function testCentrifugeAccountRequestsAndClaimsAsyncRedeemVault() public {
        MockERC20 tokenToRedeem = new MockERC20("Centrifuge Share", "CFGSHARE", 18);
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockAsyncRedeemVault asyncVault = new MockAsyncRedeemVault(tokenToRedeem, asset, 2e6);
        MockOracle oracle = new MockOracle(2e18);
        CentrifugeAccount account = _deployCentrifuge(tokenToRedeem, asset, asyncVault, oracle);

        tokenToRedeem.mint(address(account), 3 ether);

        assertEq(account.totalAssets(), 6e6);

        account.sync();

        assertEq(tokenToRedeem.balanceOf(address(account)), 0);
        assertEq(tokenToRedeem.balanceOf(address(asyncVault)), 3 ether);
        assertEq(account.totalAssets(), 6e6);

        asyncVault.fulfill(0, address(account), 3 ether);
        account.sync();

        assertEq(asset.balanceOf(address(account)), 6e6);
        assertEq(account.totalAssets(), 6e6);
    }

    function testAsyncRedeemAccountDoesNotExposeTotalRequests() public {
        MockERC20 tokenToRedeem = new MockERC20("Centrifuge Share", "CFGSHARE", 18);
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockAsyncRedeemVault asyncVault = new MockAsyncRedeemVault(tokenToRedeem, asset, 2e6);
        MockOracle oracle = new MockOracle(2e18);
        CentrifugeAccount account = _deployCentrifuge(tokenToRedeem, asset, asyncVault, oracle);

        (bool success,) = address(account).staticcall(abi.encodeWithSignature("totalRequests()"));
        assertFalse(success);
    }

    function testAsyncRedeemAccountDoesNotCapFreshPendingRequestIds() public {
        MockERC20 tokenToRedeem = new MockERC20("Centrifuge Share", "CFGSHARE", 18);
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockAsyncRedeemVault asyncVault = new MockAsyncRedeemVault(tokenToRedeem, asset, 2e6);
        MockOracle oracle = new MockOracle(2e18);
        CentrifugeAccount account = _deployCentrifuge(tokenToRedeem, asset, asyncVault, oracle);
        asyncVault.setFreshRequestIds(true);

        for (uint256 i; i < 25; ++i) {
            tokenToRedeem.mint(address(account), 1 ether);
            account.sync();
        }

        assertEq(asyncVault.nextRequestId(), 25);
        assertEq(tokenToRedeem.balanceOf(address(account)), 0);
        assertEq(account.totalAssets(), 50e6);
    }

    function testAsyncRedeemAccountPermissionlessSyncRespectsCooldown() public {
        MockERC20 tokenToRedeem = new MockERC20("Centrifuge Share", "CFGSHARE", 18);
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockAsyncRedeemVault asyncVault = new MockAsyncRedeemVault(tokenToRedeem, asset, 2e6);
        MockOracle oracle = new MockOracle(2e18);
        CentrifugeAccount account = _deployCentrifuge(tokenToRedeem, asset, asyncVault, oracle, 1 days);
        address keeper = makeAddr("keeper");

        tokenToRedeem.mint(address(account), 1 ether);
        vm.prank(keeper);
        account.sync();

        tokenToRedeem.mint(address(account), 1 ether);
        vm.prank(keeper);
        account.sync();

        assertEq(tokenToRedeem.balanceOf(address(account)), 1 ether);
        assertEq(asyncVault.pending(0, address(account)), 1 ether);
        assertEq(account.totalAssets(), 4e6);

        vm.warp(vm.getBlockTimestamp() + 1 days);
        vm.prank(keeper);
        account.sync();

        assertEq(tokenToRedeem.balanceOf(address(account)), 0);
        assertEq(asyncVault.pending(0, address(account)), 2 ether);
        assertEq(account.totalAssets(), 4e6);
    }

    function testAsyncRedeemAccountOwnerSyncBypassesCooldown() public {
        MockERC20 tokenToRedeem = new MockERC20("Centrifuge Share", "CFGSHARE", 18);
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockAsyncRedeemVault asyncVault = new MockAsyncRedeemVault(tokenToRedeem, asset, 2e6);
        MockOracle oracle = new MockOracle(2e18);
        CentrifugeAccount account = _deployCentrifuge(tokenToRedeem, asset, asyncVault, oracle, 1 days);

        tokenToRedeem.mint(address(account), 1 ether);
        account.sync();

        tokenToRedeem.mint(address(account), 1 ether);
        account.sync();

        assertEq(tokenToRedeem.balanceOf(address(account)), 0);
        assertEq(asyncVault.pending(0, address(account)), 2 ether);
        assertEq(account.totalAssets(), 4e6);
    }

    function testFigureAccountInstantRedeemsPrimeThenRequestsWyldsRedeem() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 wylds = new MockERC20("Wrapped YLDS", "wYLDS", 6);
        MockPrimeToken prime = new MockPrimeToken(wylds, 125e4);
        MockAsyncRedeemVault asyncVault = new MockAsyncRedeemVault(wylds, asset, 1e6);
        MockOracle oracle = new MockOracle(125e16);
        PRIME_Account account = _deployPrime(prime, wylds, asset, asyncVault, oracle);

        prime.mint(address(account), 100e6);

        assertEq(account.totalAssets(), 125e6);

        account.sync();

        assertEq(prime.balanceOf(address(account)), 0);
        assertEq(wylds.balanceOf(address(asyncVault)), 125e6);
        assertEq(account.totalAssets(), 125e6);

        asyncVault.fulfill(0, address(account), 125e6);
        account.sync();

        assertEq(asset.balanceOf(address(account)), 125e6);
        assertEq(account.totalAssets(), 125e6);
    }

    function testPikuAccountRequestsAndClaimsAccountableVaultRedeem() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 tokenToRedeem = new MockERC20("Morini FXArbUSDTRY", "aFXArbUSDTRY", 6);
        MockAsyncRedeemVault asyncVault = new MockAsyncRedeemVault(tokenToRedeem, asset, 1_000_393);
        MockOracle oracle = new MockOracle(1_000_393e12);
        PikuAccount account = _deployPiku(tokenToRedeem, asset, asyncVault, oracle);

        tokenToRedeem.mint(address(account), 1000e6);

        assertEq(account.totalAssets(), 1_000_393_000);

        account.sync();

        assertEq(tokenToRedeem.balanceOf(address(account)), 0);
        assertEq(tokenToRedeem.balanceOf(address(asyncVault)), 1000e6);
        assertEq(account.totalAssets(), 1_000_393_000);

        asyncVault.fulfill(0, address(account), 1000e6);
        account.sync();

        assertEq(asset.balanceOf(address(account)), 1_000_393_000);
        assertEq(account.totalAssets(), 1_000_393_000);
    }

    function testPikuFundingManagerAccountQueuesAndClaimsUspRedemption() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 tokenToRedeem = new MockERC20("Piku USP", "USP", 6);
        MockPikuFundingManager fundingManager = new MockPikuFundingManager(tokenToRedeem, asset);
        MockOracle oracle = new MockOracle(1e18);
        PikuFundingManagerAccount account = _deployPikuFundingManager(tokenToRedeem, asset, fundingManager, oracle);

        tokenToRedeem.mint(address(account), 100e6);

        account.sync();

        assertEq(tokenToRedeem.balanceOf(address(account)), 0);
        assertEq(tokenToRedeem.balanceOf(address(fundingManager)), 100e6);
        assertEq(account.pendingAssets(), 100e6);
        assertEq(account.totalAssets(), 100e6);

        fundingManager.fulfill(address(account), 100e6);
        account.sync();

        assertEq(asset.balanceOf(address(account)), 100e6);
        assertEq(account.pendingAssets(), 0);
        assertEq(account.totalAssets(), 100e6);
    }

    function testHumaAccountRequestsAndClaimsTrancheRedemption() public {
        MockERC20 tokenToRedeem = new MockERC20("Huma Senior Tranche", "HST", 18);
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockHumaTrancheVault redemptionVault = new MockHumaTrancheVault(tokenToRedeem, asset);
        MockOracle oracle = new MockOracle(2e18);
        HumaAccount account = _deployHuma(tokenToRedeem, asset, redemptionVault, oracle);

        tokenToRedeem.mint(address(account), 3 ether);

        assertEq(account.totalAssets(), 6e6);

        account.sync();

        assertEq(tokenToRedeem.balanceOf(address(account)), 0);
        assertEq(tokenToRedeem.balanceOf(address(redemptionVault)), 3 ether);
        assertEq(account.pendingAssets(), 6e6);
        assertEq(account.totalAssets(), 6e6);

        redemptionVault.fulfill(address(account), 6e6);
        account.sync();

        assertEq(asset.balanceOf(address(account)), 6e6);
        assertEq(account.pendingAssets(), 0);
        assertEq(account.totalAssets(), 6e6);
    }

    function testHumaAccountClaimsPoolClosureWithdrawal() public {
        MockERC20 tokenToRedeem = new MockERC20("Huma Junior Tranche", "HJT", 18);
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockHumaTrancheVault redemptionVault = new MockHumaTrancheVault(tokenToRedeem, asset);
        MockOracle oracle = new MockOracle(15e17);
        HumaAccount account = _deployHuma(tokenToRedeem, asset, redemptionVault, oracle);

        tokenToRedeem.mint(address(account), 2 ether);

        account.sync();
        redemptionVault.fulfillAfterClosure(address(account), 3e6);
        account.sync();

        assertEq(asset.balanceOf(address(account)), 3e6);
        assertEq(account.pendingAssets(), 0);
        assertEq(account.totalAssets(), 3e6);
    }

    function testTheoAccountRedeemsERC4626SharesIntoAsset() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockERC4626RedeemToken tokenToRedeem = new MockERC4626RedeemToken("Theo thBILL", "thBILL", 18, asset, 2e6);
        MockOracle oracle = new MockOracle(2e18);
        TheoAccount account = _deployTheo(tokenToRedeem, asset, oracle);

        tokenToRedeem.mint(address(account), 5 ether);

        assertEq(account.totalAssets(), 10e6);

        account.sync();

        assertEq(tokenToRedeem.balanceOf(address(account)), 0);
        assertEq(asset.balanceOf(address(account)), 10e6);
        assertEq(account.totalAssets(), 10e6);
    }

    function testThreeJaneAccountRedeemsERC4626SharesIntoAsset() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockERC4626RedeemToken tokenToRedeem = new MockERC4626RedeemToken("3Jane USD3", "USD3", 6, asset, 1_001_000);
        MockOracle oracle = new MockOracle(1_001_000_000_000_000_000);
        ThreeJaneAccount account = _deployThreeJane(tokenToRedeem, asset, oracle);

        tokenToRedeem.mint(address(account), 1000e6);

        assertEq(account.totalAssets(), 1001e6);

        account.sync();

        assertEq(tokenToRedeem.balanceOf(address(account)), 0);
        assertEq(asset.balanceOf(address(account)), 1001e6);
        assertEq(account.totalAssets(), 1001e6);
    }

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

    function testPSTAccountHardcodesMainnetTokenAndChainlinkFeed() public {
        vm.mockCall(PST_TOKEN_ADDRESS, abi.encodeWithSignature("decimals()"), abi.encode(uint8(6)));

        MigratablesFactory factory = new MigratablesFactory(address(this));
        address redemptionVault = makeAddr("humaRedemptionVault");
        PST_Account implementation = new PST_Account(redemptionVault, address(factory));
        ChainlinkOracle oracle = ChainlinkOracle(implementation.ORACLE());

        assertEq(implementation.TOKEN_TO_REDEEM(), PST_TOKEN_ADDRESS);
        assertEq(implementation.REDEMPTION_VAULT(), redemptionVault);
        assertEq(oracle.AGGREGATOR_0(), PST_CHAINLINK_FEED_ADDRESS);
        assertEq(oracle.AGGREGATOR_1(), address(0));
        assertEq(oracle.STALENESS_DURATION_0(), PST_STALENESS_DURATION);
        assertEq(oracle.STALENESS_DURATION_1(), 0);
    }

    function testCentrifugeTokenAccountsHardcodeEthereumMainnetTokens() public {
        MigratablesFactory factory = new MigratablesFactory(address(this));
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 share = new MockERC20("Redeem Share", "RSHARE", 18);
        MockAsyncRedeemVault asyncVault = new MockAsyncRedeemVault(share, asset, 1e6);
        MockOracle oracle = new MockOracle(1e18);

        _mockDecimals(JTRSY_TOKEN_ADDRESS, 18);
        _mockDecimals(JAAA_TOKEN_ADDRESS, 18);
        _mockDecimals(ACRDX_TOKEN_ADDRESS, 18);
        _mockDecimals(DEJTRSY_TOKEN_ADDRESS, 18);
        _mockDecimals(DEJAAA_TOKEN_ADDRESS, 18);

        assertEq(
            new JTRSY_Account(address(asyncVault), address(factory), address(oracle)).TOKEN_TO_REDEEM(),
            JTRSY_TOKEN_ADDRESS
        );
        assertEq(
            new JAAA_Account(address(asyncVault), address(factory), address(oracle)).TOKEN_TO_REDEEM(),
            JAAA_TOKEN_ADDRESS
        );
        assertEq(
            new ACRDX_Account(address(asyncVault), address(factory), address(oracle)).TOKEN_TO_REDEEM(),
            ACRDX_TOKEN_ADDRESS
        );
        assertEq(
            new deJTRSY_Account(address(asyncVault), address(factory), address(oracle)).TOKEN_TO_REDEEM(),
            DEJTRSY_TOKEN_ADDRESS
        );
        assertEq(
            new deJAAA_Account(address(asyncVault), address(factory), address(oracle)).TOKEN_TO_REDEEM(),
            DEJAAA_TOKEN_ADDRESS
        );
    }

    function testUSPAccountHardcodesCurrentPikuWorkflow() public {
        _mockDecimals(USP_TOKEN_ADDRESS, 6);

        MigratablesFactory factory = new MigratablesFactory(address(this));
        MockOracle oracle = new MockOracle(1e18);
        USP_Account account = new USP_Account(address(factory), address(oracle));

        assertEq(account.TOKEN_TO_REDEEM(), USP_TOKEN_ADDRESS);
        assertEq(account.FUNDING_MANAGER(), USP_FUNDING_MANAGER_ADDRESS);
    }

    function testSUSD3AccountHardcodesCurrentThreeJaneJuniorToken() public {
        _mockDecimals(SUSD3_TOKEN_ADDRESS, 6);

        MigratablesFactory factory = new MigratablesFactory(address(this));
        MockOracle oracle = new MockOracle(1e18);
        sUSD3_Account account = new sUSD3_Account(address(factory), address(oracle));

        assertEq(account.TOKEN_TO_REDEEM(), SUSD3_TOKEN_ADDRESS);
    }

    function _deployACRED(MockERC20 tokenToRedeem, MockERC20 asset, MockOracle oracle)
        internal
        returns (ACRED_Account account)
    {
        MigratablesFactory factory = new MigratablesFactory(address(this));
        ACRED_Account implementation =
            new ACRED_Account(address(factory), address(oracle), address(tokenToRedeem), redemptionWallet);
        factory.whitelist(address(implementation));
        account = ACRED_Account(factory.create(1, address(this), _initData(address(asset), address(tokenToRedeem))));
    }

    function _deployWstETH(
        MockWstETH wstETH,
        MockERC20 stETH,
        MockERC20 asset,
        MockLidoWithdrawalQueue withdrawalQueue,
        MockOracle oracle
    ) internal returns (wstETH_Account account) {
        MigratablesFactory factory = new MigratablesFactory(address(this));
        wstETH_Account implementation = new wstETH_Account(
            address(factory), address(oracle), address(wstETH), address(stETH), address(withdrawalQueue)
        );
        factory.whitelist(address(implementation));
        account = wstETH_Account(payable(factory.create(1, address(this), _initData(address(asset), address(wstETH)))));
    }

    function _deployWeETH(LstMocks memory mocks, MockERC20 asset, MockOracle oracle)
        internal
        returns (weETH_Account account)
    {
        MigratablesFactory factory = new MigratablesFactory(address(this));
        weETH_Account implementation = new weETH_Account(
            address(factory),
            address(oracle),
            address(mocks.weETH),
            address(mocks.eETH),
            address(mocks.liquidityPool),
            address(mocks.redemptionManager),
            address(mocks.withdrawRequestNft),
            address(mocks.weth)
        );
        factory.whitelist(address(implementation));
        account =
            weETH_Account(payable(factory.create(1, address(this), _initData(address(asset), address(mocks.weETH)))));
    }

    function _deployCentrifuge(
        MockERC20 tokenToRedeem,
        MockERC20 asset,
        MockAsyncRedeemVault asyncVault,
        MockOracle oracle
    ) internal returns (CentrifugeAccount account) {
        account = _deployCentrifuge(tokenToRedeem, asset, asyncVault, oracle, 0);
    }

    function _deployCentrifuge(
        MockERC20 tokenToRedeem,
        MockERC20 asset,
        MockAsyncRedeemVault asyncVault,
        MockOracle oracle,
        uint48 cooldown
    ) internal returns (CentrifugeAccount account) {
        MigratablesFactory factory = new MigratablesFactory(address(this));
        CentrifugeAccount implementation = new CentrifugeAccount(
            address(oracle), address(factory), cooldown, address(tokenToRedeem), address(asyncVault)
        );
        factory.whitelist(address(implementation));
        account = CentrifugeAccount(factory.create(1, address(this), _initData(address(asset), address(tokenToRedeem))));
    }

    function _deployPrime(
        MockPrimeToken prime,
        MockERC20 wylds,
        MockERC20 asset,
        MockAsyncRedeemVault asyncVault,
        MockOracle oracle
    ) internal returns (PRIME_Account account) {
        MigratablesFactory factory = new MigratablesFactory(address(this));
        PRIME_Account implementation =
            new PRIME_Account(address(asyncVault), address(prime), address(factory), address(oracle));
        factory.whitelist(address(implementation));
        account = PRIME_Account(factory.create(1, address(this), _initData(address(asset), address(prime))));
    }

    function _deployPiku(MockERC20 tokenToRedeem, MockERC20 asset, MockAsyncRedeemVault asyncVault, MockOracle oracle)
        internal
        returns (PikuAccount account)
    {
        MigratablesFactory factory = new MigratablesFactory(address(this));
        PikuAccount implementation =
            new PikuAccount(address(oracle), address(factory), 0, address(tokenToRedeem), address(asyncVault));
        factory.whitelist(address(implementation));
        account = PikuAccount(factory.create(1, address(this), _initData(address(asset), address(tokenToRedeem))));
    }

    function _deployPikuFundingManager(
        MockERC20 tokenToRedeem,
        MockERC20 asset,
        MockPikuFundingManager fundingManager,
        MockOracle oracle
    ) internal returns (PikuFundingManagerAccount account) {
        MigratablesFactory factory = new MigratablesFactory(address(this));
        PikuFundingManagerAccount implementation = new PikuFundingManagerAccount(
            address(fundingManager), address(tokenToRedeem), address(factory), address(oracle)
        );
        factory.whitelist(address(implementation));
        account = PikuFundingManagerAccount(
            factory.create(1, address(this), _initData(address(asset), address(tokenToRedeem)))
        );
    }

    function _deployHuma(
        MockERC20 tokenToRedeem,
        MockERC20 asset,
        MockHumaTrancheVault redemptionVault,
        MockOracle oracle
    ) internal returns (HumaAccount account) {
        MigratablesFactory factory = new MigratablesFactory(address(this));
        HumaAccount implementation =
            new HumaAccount(address(redemptionVault), address(tokenToRedeem), address(factory), address(oracle));
        factory.whitelist(address(implementation));
        account = HumaAccount(factory.create(1, address(this), _initData(address(asset), address(tokenToRedeem))));
    }

    function _deployTheo(MockERC4626RedeemToken tokenToRedeem, MockERC20 asset, MockOracle oracle)
        internal
        returns (TheoAccount account)
    {
        MigratablesFactory factory = new MigratablesFactory(address(this));
        TheoAccount implementation = new TheoAccount(address(tokenToRedeem), address(factory), address(oracle));
        factory.whitelist(address(implementation));
        account = TheoAccount(factory.create(1, address(this), _initData(address(asset), address(tokenToRedeem))));
    }

    function _deployThreeJane(MockERC4626RedeemToken tokenToRedeem, MockERC20 asset, MockOracle oracle)
        internal
        returns (ThreeJaneAccount account)
    {
        MigratablesFactory factory = new MigratablesFactory(address(this));
        ThreeJaneAccount implementation =
            new ThreeJaneAccount(address(tokenToRedeem), address(factory), address(oracle));
        factory.whitelist(address(implementation));
        account = ThreeJaneAccount(factory.create(1, address(this), _initData(address(asset), address(tokenToRedeem))));
    }

    function _deployDigiFT(MockERC20 tokenToRedeem, MockERC20 asset, MockOracle oracle)
        internal
        returns (DigiFTAccount account)
    {
        MigratablesFactory factory = new MigratablesFactory(address(this));
        DigiFTAccount implementation =
            new DigiFTAccount(redemptionWallet, address(tokenToRedeem), address(factory), address(oracle));
        factory.whitelist(address(implementation));
        account = DigiFTAccount(factory.create(1, address(this), _initData(address(asset), address(tokenToRedeem))));
    }

    function _lstMocks() internal returns (LstMocks memory mocks) {
        mocks.stETH = new MockERC20("Liquid staked Ether", "stETH", 18);
        mocks.eETH = new MockERC20("ether.fi ETH", "eETH", 18);
        mocks.weth = new MockWETH();
        mocks.wstETH = new MockWstETH(address(mocks.stETH));
        mocks.weETH = new MockWeETH(address(mocks.eETH));
        mocks.redemptionManager =
            new MockEtherFiRedemptionManager(address(mocks.weETH), address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE));
        mocks.liquidityPool = new MockEtherFiLiquidityPool(address(mocks.eETH));
        mocks.withdrawRequestNft = new MockEtherFiWithdrawRequestNFT();
    }

    function _initData(address asset, address tokenToRedeem) internal returns (bytes memory) {
        address[] memory converters = new address[](0);
        return abi.encode(
            IAccount.InitParams({
                adapter: adapter,
                vault: address(_vault(MockERC20(asset))),
                tokenToRedeem: tokenToRedeem,
                converters: converters
            })
        );
    }

    function _vault(MockERC20 asset) internal returns (MockVault vault) {
        vault = new MockVault(address(asset));
    }

    function _mockDecimals(address token, uint8 decimals_) internal {
        vm.mockCall(token, abi.encodeWithSignature("decimals()"), abi.encode(decimals_));
    }
}

struct LstMocks {
    MockERC20 stETH;
    MockERC20 eETH;
    MockWETH weth;
    MockWstETH wstETH;
    MockWeETH weETH;
    MockEtherFiRedemptionManager redemptionManager;
    MockEtherFiLiquidityPool liquidityPool;
    MockEtherFiWithdrawRequestNFT withdrawRequestNft;
}

contract MockOracle {
    uint256 internal _price;

    constructor(uint256 price_) {
        _price = price_;
    }

    function setPrice(uint256 price_) external {
        _price = price_;
    }

    function getPrice() external view returns (uint256) {
        return _price;
    }
}

contract MockVault {
    address public immutable asset;

    constructor(address asset_) {
        asset = asset_;
    }
}

contract MockERC20 is ERC20 {
    uint8 internal immutable _decimals;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}

contract MockWETH is MockERC20 {
    constructor() MockERC20("Wrapped Ether", "WETH", 18) {}

    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }
}

contract MockWstETH is MockERC20 {
    MockERC20 internal immutable _stETH;

    constructor(address stETH_) MockERC20("Wrapped stETH", "wstETH", 18) {
        _stETH = MockERC20(stETH_);
    }

    function wrap(uint256 stETHAmount) external returns (uint256 wstETHAmount) {
        IERC20(address(_stETH)).transferFrom(msg.sender, address(this), stETHAmount);
        _mint(msg.sender, stETHAmount);
        return stETHAmount;
    }

    function unwrap(uint256 wstETHAmount) external returns (uint256 stETHAmount) {
        _burn(msg.sender, wstETHAmount);
        _stETH.mint(msg.sender, wstETHAmount);
        return wstETHAmount;
    }

    function getWstETHByStETH(uint256 stETHAmount) external pure returns (uint256 wstETHAmount) {
        return stETHAmount;
    }

    function getStETHByWstETH(uint256 wstETHAmount) external pure returns (uint256 stETHAmount) {
        return wstETHAmount;
    }
}

contract MockLidoWithdrawalQueue {
    IERC20 internal immutable _wstETH;
    IERC20 internal immutable _stETH;

    uint256 public constant MAX_STETH_WITHDRAWAL_AMOUNT = 1000 ether;
    uint256 public constant MIN_STETH_WITHDRAWAL_AMOUNT = 100;

    uint256 public nextRequestId = 1;

    mapping(uint256 requestId => uint256 amount) public requestedWstETH;
    mapping(uint256 requestId => uint256 amount) public requestedStETH;
    mapping(uint256 requestId => uint256 amount) public claimAmount;

    constructor(address wstETH_, address stETH_) {
        _wstETH = IERC20(wstETH_);
        _stETH = IERC20(stETH_);
    }

    function requestWithdrawalsWstETH(uint256[] calldata amounts, address) external returns (uint256[] memory ids) {
        ids = new uint256[](amounts.length);
        for (uint256 i; i < amounts.length; ++i) {
            _wstETH.transferFrom(msg.sender, address(this), amounts[i]);
            ids[i] = nextRequestId++;
            requestedWstETH[ids[i]] = amounts[i];
        }
    }

    function requestWithdrawals(uint256[] calldata amounts, address) external returns (uint256[] memory ids) {
        ids = new uint256[](amounts.length);
        for (uint256 i; i < amounts.length; ++i) {
            _stETH.transferFrom(msg.sender, address(this), amounts[i]);
            ids[i] = nextRequestId++;
            requestedStETH[ids[i]] = amounts[i];
        }
    }

    function setClaimAmount(uint256 requestId, uint256 amount) external payable {
        claimAmount[requestId] = amount;
    }

    function claimWithdrawal(uint256 requestId) external {
        uint256 amount = claimAmount[requestId];
        if (amount == 0) {
            revert();
        }
        claimAmount[requestId] = 0;
        (bool success,) = msg.sender.call{value: amount}("");
        require(success);
    }
}

contract MockWeETH is MockERC20 {
    MockERC20 internal immutable _eETH;

    constructor(address eETH_) MockERC20("Wrapped eETH", "weETH", 18) {
        _eETH = MockERC20(eETH_);
    }

    function unwrap(uint256 weETHAmount) external returns (uint256 eETHAmount) {
        _burn(msg.sender, weETHAmount);
        _eETH.mint(msg.sender, weETHAmount);
        return weETHAmount;
    }

    function getEETHByWeETH(uint256 weETHAmount) external pure returns (uint256 eETHAmount) {
        return weETHAmount;
    }
}

contract MockPrimeToken is MockERC20 {
    MockERC20 internal immutable _wylds;
    uint256 internal immutable _wyldsPerPrime;

    constructor(MockERC20 wylds_, uint256 wyldsPerPrime_) MockERC20("Hastra PRIME", "PRIME", 6) {
        _wylds = wylds_;
        _wyldsPerPrime = wyldsPerPrime_;
    }

    function asset() external view returns (address) {
        return address(_wylds);
    }

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }
        _burn(owner, shares);
        assets = shares * _wyldsPerPrime / 1e6;
        _wylds.mint(receiver, assets);
    }
}

contract MockERC4626RedeemToken is MockERC20 {
    MockERC20 internal immutable _asset;
    uint256 internal immutable _assetsPerShare;

    constructor(string memory name_, string memory symbol_, uint8 decimals_, MockERC20 asset_, uint256 assetsPerShare_)
        MockERC20(name_, symbol_, decimals_)
    {
        _asset = asset_;
        _assetsPerShare = assetsPerShare_;
    }

    function asset() external view returns (address) {
        return address(_asset);
    }

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }
        _burn(owner, shares);
        assets = shares * _assetsPerShare / 10 ** decimals();
        _asset.mint(receiver, assets);
    }
}

contract MockHumaTrancheVault {
    MockERC20 public immutable share;
    MockERC20 public immutable asset;

    mapping(address account => uint256 assets) public claimableAssets;
    mapping(address account => uint256 assets) public closureAssets;

    constructor(MockERC20 share_, MockERC20 asset_) {
        share = share_;
        asset = asset_;
    }

    function addRedemptionRequest(uint256 shares) external {
        IERC20(address(share)).transferFrom(msg.sender, address(this), shares);
    }

    function fulfill(address account, uint256 assets) external {
        claimableAssets[account] += assets;
    }

    function fulfillAfterClosure(address account, uint256 assets) external {
        closureAssets[account] += assets;
    }

    function disburse() external {
        uint256 assets = claimableAssets[msg.sender];
        claimableAssets[msg.sender] = 0;
        asset.mint(msg.sender, assets);
    }

    function withdrawAfterPoolClosure() external {
        uint256 assets = closureAssets[msg.sender];
        closureAssets[msg.sender] = 0;
        asset.mint(msg.sender, assets);
    }
}

contract MockAsyncRedeemVault {
    MockERC20 public immutable share;
    MockERC20 public immutable asset;
    uint256 public immutable assetsPerShare;
    bool public freshRequestIds;
    uint256 public nextRequestId;

    mapping(uint256 requestId => mapping(address controller => uint256 shares)) public pending;
    mapping(uint256 requestId => mapping(address controller => uint256 shares)) public claimable;

    constructor(MockERC20 share_, MockERC20 asset_, uint256 assetsPerShare_) {
        share = share_;
        asset = asset_;
        assetsPerShare = assetsPerShare_;
    }

    function setFreshRequestIds(bool status) external {
        freshRequestIds = status;
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        return shares * assetsPerShare / 10 ** share.decimals();
    }

    function requestRedeem(uint256 shares, address controller, address owner) external returns (uint256 requestId) {
        if (freshRequestIds) {
            requestId = nextRequestId++;
        }
        IERC20(address(share)).transferFrom(owner, address(this), shares);
        pending[requestId][controller] += shares;
    }

    function pendingRedeemRequest(uint256 requestId, address controller) external view returns (uint256 shares) {
        return pending[requestId][controller];
    }

    function claimableRedeemRequest(uint256 requestId, address controller) external view returns (uint256 shares) {
        return claimable[requestId][controller];
    }

    function fulfill(uint256 requestId, address controller, uint256 shares) external {
        pending[requestId][controller] -= shares;
        claimable[requestId][controller] += shares;
    }

    function redeem(uint256 shares, address receiver, address controller) external returns (uint256 assets) {
        claimable[0][controller] -= shares;
        assets = convertToAssets(shares);
        asset.mint(receiver, assets);
    }
}

contract MockPikuFundingManager {
    MockERC20 public immutable token;
    MockERC20 public immutable asset;

    mapping(address account => uint256 assets) public claimableAssets;

    constructor(MockERC20 token_, MockERC20 asset_) {
        token = token_;
        asset = asset_;
    }

    function sell(uint256 depositAmount, uint256) external {
        IERC20(address(token)).transferFrom(msg.sender, address(this), depositAmount);
    }

    function fulfill(address account, uint256 assets) external {
        claimableAssets[account] += assets;
    }

    function claim() external {
        uint256 assets = claimableAssets[msg.sender];
        claimableAssets[msg.sender] = 0;
        asset.mint(msg.sender, assets);
    }
}

contract MockEtherFiRedemptionManager {
    address public immutable weETH;
    address public immutable ETH_ADDRESS;

    mapping(address token => uint16 fee) public exitFeeInBps;
    mapping(address token => bool status) public redeemable;

    address public lastOutputToken;
    address public lastReceiver;
    uint256 public lastWeETHAmount;

    constructor(address weETH_, address ethAddress_) {
        weETH = weETH_;
        ETH_ADDRESS = ethAddress_;
    }

    function setExitFee(address token, uint16 fee) external {
        exitFeeInBps[token] = fee;
    }

    function setRedeemable(address token, bool status) external {
        redeemable[token] = status;
    }

    function tokenToRedemptionInfo(address token)
        external
        view
        returns (BucketLimit memory limit, uint16, uint16 exitFeeInBps_, uint16)
    {
        return (limit, 0, exitFeeInBps[token], 0);
    }

    function canRedeem(uint256, address token) external view returns (bool) {
        return redeemable[token];
    }

    function redeemWeEth(uint256 weETHAmount, address receiver, address outputToken) external {
        IERC20(weETH).transferFrom(msg.sender, address(this), weETHAmount);

        lastWeETHAmount = weETHAmount;
        lastReceiver = receiver;
        lastOutputToken = outputToken;

        if (outputToken == ETH_ADDRESS) {
            (bool success,) = receiver.call{value: weETHAmount}("");
            require(success);
        } else {
            MockERC20(outputToken).mint(receiver, weETHAmount);
        }
    }

    struct BucketLimit {
        uint64 capacity;
        uint64 remaining;
        uint64 lastRefill;
        uint64 refillRate;
    }
}

contract MockEtherFiLiquidityPool {
    IERC20 internal immutable _eETH;

    address public lastRecipient;
    uint256 public lastAmount;
    uint256 public nextRequestId = 1;

    constructor(address eETH_) {
        _eETH = IERC20(eETH_);
    }

    function requestWithdraw(address recipient, uint256 amount) external returns (uint256 requestId) {
        _eETH.transferFrom(msg.sender, address(this), amount);
        lastRecipient = recipient;
        lastAmount = amount;
        requestId = nextRequestId++;
    }
}

contract MockEtherFiWithdrawRequestNFT {
    mapping(uint256 requestId => uint256 amount) public claimAmount;

    function setClaimAmount(uint256 claimAmount_) external payable {
        claimAmount[1] = claimAmount_;
    }

    function claimWithdraw(uint256 requestId) external {
        uint256 amount = claimAmount[requestId];
        if (amount == 0) {
            revert();
        }
        claimAmount[requestId] = 0;
        (bool success,) = msg.sender.call{value: amount}("");
        require(success);
    }
}
