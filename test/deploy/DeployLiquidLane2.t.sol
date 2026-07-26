// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {DeployLiquidLane2Script} from "../../script/deploy/adapters/DeployLiquidLane2.s.sol";
import {CentrifugeAccount} from "../../src/contracts/adapters/ll-adapter/CentrifugeAccount.sol";
import {AsyncRedeemOracle} from "../../src/contracts/adapters/ll-adapter/oracles/AsyncRedeemOracle.sol";
import {IAsyncRedeemAccount} from "../../src/interfaces/adapters/ll-adapter/IAsyncRedeemAccount.sol";
import {IAsyncRedeemVault} from "../../src/interfaces/adapters/ll-adapter/IAsyncRedeemVault.sol";
import {ICooldownAccount} from "../../src/interfaces/adapters/ll-adapter/ICooldownAccount.sol";
import {IERC7575Share} from "../../src/interfaces/adapters/ll-adapter/IERC7575Share.sol";
import {IAccount} from "../../src/interfaces/adapters/ll-adapter/IAccount.sol";
import {IMidasOracle} from "../../src/interfaces/adapters/ll-adapter/midas/IMidasOracle.sol";
import {IMidasRedemptionVault} from "../../src/interfaces/adapters/ll-adapter/midas/IMidasRedemptionVault.sol";
import {ICoWSwapConverter, ICoWSwapSettlement} from "../../src/interfaces/adapters/common/ICoWSwapConverter.sol";
import {IMigratableEntity} from "../../src/interfaces/common/IMigratableEntity.sol";
import {MigratablesFactory} from "../../src/contracts/common/MigratablesFactory.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract DeployLiquidLane2ScriptHarness is DeployLiquidLane2Script {
    function _startBroadcast() internal override {}

    function _stopBroadcast() internal override {}

    function _scriptOwner() internal view override returns (address) {
        return address(this);
    }
}

contract DeployLiquidLane2Test is Test {
    address internal constant WYLDS = 0x6aD038cA6C04e885630851278ca0a856Ad9a66Cc;
    address internal constant WYLDS_REDEEM_VAULT = 0xA8C3CF6183D49d5D372f8FC149BD2cb5CFC0faCd;

    DeployLiquidLane2ScriptHarness internal harness;

    address internal centrifugeRoot;
    address[5] internal tokens;
    address[5] internal asyncRedeemVaults;
    uint256[5] internal referencePrices;
    uint256[5] internal minPrices;
    uint256[5] internal maxPrices;

    function setUp() public {
        harness = new DeployLiquidLane2ScriptHarness();
        vm.chainId(1);
        vm.etch(harness.FACTORIES_OWNER(), hex"00");
        vm.mockCall(harness.FACTORIES_OWNER(), abi.encodeWithSignature("getThreshold()"), abi.encode(uint256(2)));

        tokens = [harness.JAAA(), harness.JTRSY(), harness.HYB(), harness.DEJAAA(), harness.DEJTRSY()];
        referencePrices = [
            uint256(1_041_654_000_000_000_000),
            1_110_250_000_000_000_000,
            1_003_773_000_000_000_000,
            1_040_148_000_000_000_000,
            1_031_458_000_000_000_000
        ];
        minPrices = [
            harness.JAAA_MIN_PRICE(),
            harness.JTRSY_MIN_PRICE(),
            harness.HYB_MIN_PRICE(),
            harness.DEJAAA_MIN_PRICE(),
            harness.DEJTRSY_MIN_PRICE()
        ];
        maxPrices = [
            harness.JAAA_MAX_PRICE(),
            harness.JTRSY_MAX_PRICE(),
            harness.HYB_MAX_PRICE(),
            harness.DEJAAA_MAX_PRICE(),
            harness.DEJTRSY_MAX_PRICE()
        ];

        vm.mockCall(harness.USDC(), abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(uint8(6)));
        vm.mockCall(
            harness.COW_SWAP_SETTLEMENT(),
            abi.encodeWithSelector(ICoWSwapSettlement.vaultRelayer.selector),
            abi.encode(makeAddr("cowSwapVaultRelayer"))
        );

        centrifugeRoot = makeAddr("centrifugeRoot");
        vm.etch(centrifugeRoot, hex"00");
        vm.mockCall(centrifugeRoot, abi.encodeWithSignature("paused()"), abi.encode(false));

        for (uint256 i; i < tokens.length; ++i) {
            uint8 decimals = i < 2 ? 6 : 18;
            address asyncRedeemVault = address(uint160(0x1000 + i));
            address hook = address(uint160(0x2000 + i));
            asyncRedeemVaults[i] = asyncRedeemVault;

            vm.mockCall(tokens[i], abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(decimals));
            vm.etch(hook, hex"00");
            vm.mockCall(tokens[i], abi.encodeWithSignature("hook()"), abi.encode(hook));
            vm.mockCall(
                tokens[i],
                abi.encodeWithSelector(IERC7575Share.vault.selector, harness.USDC()),
                abi.encode(asyncRedeemVault)
            );
            vm.mockCall(
                asyncRedeemVault, abi.encodeWithSelector(IAsyncRedeemVault.asset.selector), abi.encode(harness.USDC())
            );
            vm.mockCall(asyncRedeemVault, abi.encodeWithSignature("share()"), abi.encode(tokens[i]));
            vm.mockCall(asyncRedeemVault, abi.encodeWithSignature("root()"), abi.encode(centrifugeRoot));
            vm.mockCall(
                asyncRedeemVault,
                abi.encodeWithSelector(IAsyncRedeemVault.convertToAssets.selector, 10 ** decimals),
                abi.encode(referencePrices[i] / 1e12)
            );
        }

        _stubOpenEden();
        _stubFigure();
        _stubMGlobal();
    }

    function testRunRejectsNonMainnet() public {
        vm.chainId(31_337);
        vm.expectRevert("not ethereum mainnet");
        harness.run();
    }

    function testRunRejectsUnsafeFactoryOwner() public {
        vm.mockCall(harness.FACTORIES_OWNER(), abi.encodeWithSignature("getThreshold()"), abi.encode(uint256(1)));
        vm.expectRevert("unsafe factories owner threshold");
        harness.run();
    }

    function testRunLogsRequiredProviderOnboarding() public {
        vm.writeFile("script/logs.txt", "");
        harness.run();

        string memory logs = vm.readFile("script/logs.txt");
        assertTrue(vm.contains(logs, "permission the LiquidLaneAdapter proxy and every Centrifuge account proxy"));
        assertTrue(vm.contains(logs, "greenlist the LiquidLaneAdapter proxy, every mGLOBAL account proxy"));
        assertTrue(vm.contains(logs, "all direct mGLOBAL transfer counterparties"));
        assertTrue(vm.contains(logs, "KYC-list the LiquidLaneAdapter proxy"));
        assertTrue(vm.contains(logs, "100 HYBOND"));
        assertTrue(vm.contains(logs, "1 mGLOBAL"));
    }

    function testRunDoesNotDeployACRDX() public {
        vm.writeFile("script/logs.txt", "");
        harness.run();

        assertFalse(vm.contains(vm.readFile("script/logs.txt"), "Deployed ACRDX account"));
    }

    function testRunRejectsMissingCentrifugeTransferHook() public {
        vm.mockCall(harness.JAAA(), abi.encodeWithSignature("hook()"), abi.encode(address(0)));
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x01));
        harness.run();
    }

    function testRunRejectsMismatchedCentrifugeVaultShare() public {
        vm.mockCall(asyncRedeemVaults[0], abi.encodeWithSignature("share()"), abi.encode(makeAddr("wrongShare")));
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x01));
        harness.run();
    }

    function testRunRejectsPausedCentrifugeRoot() public {
        vm.mockCall(centrifugeRoot, abi.encodeWithSignature("paused()"), abi.encode(true));
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x01));
        harness.run();
    }

    function testRunRejectsWrongMGlobalRedemptionVaultToken() public {
        vm.mockCall(
            harness.MGLOBAL_REDEMPTION_VAULT(), abi.encodeWithSignature("mToken()"), abi.encode(makeAddr("wrongToken"))
        );
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x01));
        harness.run();
    }

    function testRunRejectsUnavailableMGlobalUsdcRedemption() public {
        vm.mockCall(
            harness.MGLOBAL_REDEMPTION_VAULT(),
            abi.encodeWithSignature("tokensConfig(address)", harness.USDC()),
            abi.encode(address(0), uint256(0), uint256(0), false)
        );
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x01));
        harness.run();
    }

    function testRunRejectsPausedMGlobalVault() public {
        vm.mockCall(harness.MGLOBAL_REDEMPTION_VAULT(), abi.encodeWithSignature("paused()"), abi.encode(true));
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x01));
        harness.run();
    }

    function testRunRejectsPausedMGlobalRedemptionRequests() public {
        vm.mockCall(
            harness.MGLOBAL_REDEMPTION_VAULT(),
            abi.encodeWithSignature("fnPaused(bytes4)", IMidasRedemptionVault.redeemRequest.selector),
            abi.encode(true)
        );
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x01));
        harness.run();
    }

    function testRunRejectsPausedMGlobalToken() public {
        vm.mockCall(harness.MGLOBAL(), abi.encodeWithSignature("paused()"), abi.encode(true));
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x01));
        harness.run();
    }

    function testRunRejectsWrongMGlobalRedemptionMinimum() public {
        vm.mockCall(harness.MGLOBAL_REDEMPTION_VAULT(), abi.encodeWithSignature("minAmount()"), abi.encode(2 ether));
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x01));
        harness.run();
    }

    function testRunRejectsMismatchedMGlobalGreenlistRole() public {
        vm.mockCall(
            harness.MGLOBAL_REDEMPTION_VAULT(),
            abi.encodeWithSignature("greenlistedRole()"),
            abi.encode(bytes32(uint256(1)))
        );
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x01));
        harness.run();
    }

    function testRunRejectsDisabledMGlobalGreenlist() public {
        vm.mockCall(
            harness.MGLOBAL_REDEMPTION_VAULT(), abi.encodeWithSignature("greenlistEnabled()"), abi.encode(false)
        );
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x01));
        harness.run();
    }

    function testRunRejectsWrongMGlobalPriceAdjustment() public {
        vm.mockCall(
            makeAddr("mGlobalAggregator"), abi.encodeWithSignature("adjustmentPercentage()"), abi.encode(int256(-5e8))
        );
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x01));
        harness.run();
    }

    function testOracleBoundsAreTwentyFiveAndThreeHundredFiftyPercentOfReferencePrices() public view {
        uint256[8] memory referencePrices = [
            uint256(1_041_654_000_000_000_000),
            1_110_250_000_000_000_000,
            1_003_773_000_000_000_000,
            1_040_148_000_000_000_000,
            1_031_458_000_000_000_000,
            1_734_996_000_000_000_000,
            1_049_663_000_000_000_000,
            1_005_764_800_000_000_000
        ];
        uint256[8] memory configuredMinPrices = [
            harness.JAAA_MIN_PRICE(),
            harness.JTRSY_MIN_PRICE(),
            harness.HYB_MIN_PRICE(),
            harness.DEJAAA_MIN_PRICE(),
            harness.DEJTRSY_MIN_PRICE(),
            harness.HYBOND_MIN_PRICE(),
            harness.PRIME_MIN_PRICE(),
            harness.MGLOBAL_MIN_PRICE()
        ];
        uint256[8] memory configuredMaxPrices = [
            harness.JAAA_MAX_PRICE(),
            harness.JTRSY_MAX_PRICE(),
            harness.HYB_MAX_PRICE(),
            harness.DEJAAA_MAX_PRICE(),
            harness.DEJTRSY_MAX_PRICE(),
            harness.HYBOND_MAX_PRICE(),
            harness.PRIME_MAX_PRICE(),
            harness.MGLOBAL_MAX_PRICE()
        ];

        for (uint256 i; i < referencePrices.length; ++i) {
            assertEq(configuredMinPrices[i], referencePrices[i] / 4);
            assertEq(configuredMaxPrices[i], referencePrices[i] * 7 / 2);
        }
    }

    function testFigureAddressesAreExplicitDeploymentConfig() public view {
        (bool wyldsSuccess, bytes memory wyldsData) = address(harness).staticcall(abi.encodeWithSignature("WYLDS()"));
        (bool vaultSuccess, bytes memory vaultData) =
            address(harness).staticcall(abi.encodeWithSignature("WYLDS_REDEEM_VAULT()"));

        assertTrue(wyldsSuccess);
        assertTrue(vaultSuccess);
        assertEq(abi.decode(wyldsData, (address)), WYLDS);
        assertEq(abi.decode(vaultData, (address)), WYLDS_REDEEM_VAULT);
    }

    function testHybondMinimumIsExplicitDeploymentConfig() public view {
        (bool success, bytes memory data) =
            address(harness).staticcall(abi.encodeWithSignature("HYBOND_REDEEM_MINIMUM()"));

        assertTrue(success);
        assertEq(abi.decode(data, (uint256)), 100 ether);
    }

    function testMGlobalMinimumIsExplicitDeploymentConfig() public view {
        assertEq(harness.MGLOBAL_REDEEM_MINIMUM(), 1 ether);
    }

    function testMGlobalOracleUsesImmutableMarketDataFeed() public {
        DeployLiquidLane2Script.LiquidLane2DeploymentData memory data = harness.run();

        assertEq(IMidasOracle(data.mGlobal.oracle).DATA_FEED(), 0x517cf115e750d02aeB978011fCE05691613d7ed7);
    }

    function testHybondCooldownIsEighteenHours() public {
        DeployLiquidLane2Script.LiquidLane2DeploymentData memory data = harness.run();

        assertEq(harness.HYBOND_COOLDOWN(), 18 hours);
        assertEq(ICooldownAccount(data.hybond.implementation).COOLDOWN(), 18 hours);
    }

    function testPrimeCooldownIsEighteenHours() public {
        DeployLiquidLane2Script.LiquidLane2DeploymentData memory data = harness.run();

        assertEq(harness.FIGURE_COOLDOWN(), 18 hours);
        assertEq(ICooldownAccount(data.prime.implementation).COOLDOWN(), 18 hours);
    }

    function testRunRejectsWrongOpenEdenToken() public {
        vm.mockCall(harness.HYBOND_EXPRESS(), abi.encodeWithSignature("token()"), abi.encode(makeAddr("wrongToken")));
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x01));
        harness.run();
    }

    function testRunRejectsPausedOpenEdenRedemptions() public {
        vm.mockCall(harness.HYBOND_EXPRESS(), abi.encodeWithSignature("pausedRedeem()"), abi.encode(true));
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x01));
        harness.run();
    }

    function testRunRejectsMismatchedOpenEdenKycManager() public {
        vm.mockCall(
            harness.HYBOND_EXPRESS(), abi.encodeWithSignature("kycManager()"), abi.encode(makeAddr("wrongKycManager"))
        );
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x01));
        harness.run();
    }

    function testRunRejectsUnkycedOpenEdenExpress() public {
        vm.mockCall(
            makeAddr("openEdenKycManager"),
            abi.encodeWithSignature("isKyced(address)", harness.HYBOND_EXPRESS()),
            abi.encode(false)
        );
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x01));
        harness.run();
    }

    function testRunRejectsWrongFigureYieldVault() public {
        vm.mockCall(harness.PRIME(), abi.encodeWithSignature("yieldVault()"), abi.encode(makeAddr("wrongYieldVault")));
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x01));
        harness.run();
    }

    function testRunRejectsPausedFigureStack() public {
        vm.mockCall(WYLDS, abi.encodeWithSignature("paused()"), abi.encode(true));
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x01));
        harness.run();
    }

    /// @dev Stubs the OpenEden HYBOND surface the deploy + validation reads (no proxy is created, so
    ///      only constructor getters and oracle `getPrice` are exercised).
    function _stubOpenEden() internal {
        address kycManager = makeAddr("openEdenKycManager");
        vm.mockCall(harness.HYBOND(), abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(uint8(18)));
        vm.mockCall(harness.HYBOND(), abi.encodeWithSignature("kycManager()"), abi.encode(kycManager));
        vm.mockCall(harness.HYBOND(), abi.encodeWithSignature("paused()"), abi.encode(false));
        vm.mockCall(harness.HYBOND_EXPRESS(), abi.encodeWithSignature("token()"), abi.encode(harness.HYBOND()));
        vm.mockCall(harness.HYBOND_EXPRESS(), abi.encodeWithSignature("kycManager()"), abi.encode(kycManager));
        vm.mockCall(kycManager, abi.encodeWithSignature("isKyced(address)", harness.HYBOND_EXPRESS()), abi.encode(true));
        vm.mockCall(harness.HYBOND_EXPRESS(), abi.encodeWithSignature("pausedRedeem()"), abi.encode(false));
        vm.mockCall(harness.HYBOND_EXPRESS(), abi.encodeWithSignature("redeemMinimum()"), abi.encode(100 ether));
        vm.mockCall(harness.HYBOND_EXPRESS(), abi.encodeWithSignature("redeemFeeRate()"), abi.encode(uint256(0)));
        vm.mockCall(harness.HYBOND_EXPRESS(), abi.encodeWithSignature("redeemAsset()"), abi.encode(harness.USDC()));
        // previewRedeem(tokenAmount) -> (fee, gross, net); net drives the 1e18-scaled oracle price.
        vm.mockCall(
            harness.HYBOND_EXPRESS(),
            abi.encodeWithSignature("previewRedeem(uint256)"),
            abi.encode(uint256(0), uint256(1_734_996), uint256(1_734_996))
        );
    }

    /// @dev Stubs the Figure PRIME surface through the wYLDS yield vault.
    function _stubFigure() internal {
        vm.mockCall(WYLDS, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(uint8(6)));
        vm.mockCall(WYLDS, abi.encodeWithSignature("asset()"), abi.encode(harness.USDC()));
        vm.mockCall(WYLDS, abi.encodeWithSignature("convertToAssets(uint256)"), abi.encode(uint256(1_049_663)));
        vm.mockCall(WYLDS, abi.encodeWithSignature("paused()"), abi.encode(false));
        vm.mockCall(WYLDS, abi.encodeWithSignature("redeemVault()"), abi.encode(WYLDS_REDEEM_VAULT));

        vm.mockCall(harness.PRIME(), abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(uint8(6)));
        vm.mockCall(harness.PRIME(), abi.encodeWithSignature("asset()"), abi.encode(WYLDS));
        vm.mockCall(harness.PRIME(), abi.encodeWithSignature("yieldVault()"), abi.encode(WYLDS));
        vm.mockCall(
            harness.PRIME(), abi.encodeWithSignature("convertToAssets(uint256)"), abi.encode(uint256(1_049_663))
        );
        vm.mockCall(harness.PRIME(), abi.encodeWithSignature("paused()"), abi.encode(false));
    }

    /// @dev Stubs the Midas mGLOBAL surface the account constructor + validation reads.
    function _stubMGlobal() internal {
        address accessControl = makeAddr("midasAccessControl");
        bytes32 greenlistedRole = keccak256("M_GLOBAL_GREENLISTED_ROLE");

        vm.mockCall(harness.MGLOBAL(), abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(uint8(18)));
        vm.mockCall(harness.MGLOBAL(), abi.encodeWithSignature("paused()"), abi.encode(false));
        vm.mockCall(harness.MGLOBAL(), abi.encodeWithSignature("accessControl()"), abi.encode(accessControl));
        vm.mockCall(
            harness.MGLOBAL(), abi.encodeWithSignature("M_GLOBAL_GREENLISTED_ROLE()"), abi.encode(greenlistedRole)
        );
        vm.mockCall(
            harness.MGLOBAL_REDEMPTION_VAULT(), abi.encodeWithSignature("mToken()"), abi.encode(harness.MGLOBAL())
        );
        vm.mockCall(
            harness.MGLOBAL_REDEMPTION_VAULT(),
            abi.encodeWithSignature("mTokenDataFeed()"),
            abi.encode(harness.MGLOBAL_REDEMPTION_DATA_FEED())
        );
        vm.mockCall(
            harness.MGLOBAL_REDEMPTION_VAULT(),
            abi.encodeWithSignature("tokensConfig(address)", harness.USDC()),
            abi.encode(makeAddr("usdcDataFeed"), uint256(0), type(uint256).max, true)
        );
        vm.mockCall(harness.MGLOBAL_REDEMPTION_VAULT(), abi.encodeWithSignature("paused()"), abi.encode(false));
        vm.mockCall(
            harness.MGLOBAL_REDEMPTION_VAULT(),
            abi.encodeWithSignature("fnPaused(bytes4)", IMidasRedemptionVault.redeemRequest.selector),
            abi.encode(false)
        );
        vm.mockCall(harness.MGLOBAL_REDEMPTION_VAULT(), abi.encodeWithSignature("greenlistEnabled()"), abi.encode(true));
        vm.mockCall(harness.MGLOBAL_REDEMPTION_VAULT(), abi.encodeWithSignature("minAmount()"), abi.encode(1 ether));
        vm.mockCall(
            harness.MGLOBAL_REDEMPTION_VAULT(), abi.encodeWithSignature("accessControl()"), abi.encode(accessControl)
        );
        vm.mockCall(
            harness.MGLOBAL_REDEMPTION_VAULT(),
            abi.encodeWithSignature("greenlistedRole()"),
            abi.encode(greenlistedRole)
        );
        vm.etch(accessControl, hex"00");
        vm.mockCall(
            accessControl,
            abi.encodeWithSignature("hasRole(bytes32,address)", greenlistedRole, harness.MGLOBAL_REDEMPTION_VAULT()),
            abi.encode(true)
        );
        address aggregator = makeAddr("mGlobalAggregator");
        vm.mockCall(
            harness.MGLOBAL_DATA_FEED(),
            abi.encodeWithSignature("aggregator()"),
            abi.encode(harness.MGLOBAL_MARKET_AGGREGATOR())
        );
        vm.mockCall(
            harness.MGLOBAL_REDEMPTION_DATA_FEED(), abi.encodeWithSignature("aggregator()"), abi.encode(aggregator)
        );
        vm.mockCall(
            aggregator, abi.encodeWithSignature("underlyingFeed()"), abi.encode(harness.MGLOBAL_MARKET_AGGREGATOR())
        );
        vm.mockCall(aggregator, abi.encodeWithSignature("adjustmentPercentage()"), abi.encode(int256(-7e8)));
        vm.mockCall(aggregator, abi.encodeWithSignature("decimals()"), abi.encode(uint8(8)));
        // getDataInBase18 must sit inside the configured mGLOBAL MidasOracle bounds.
        vm.mockCall(
            harness.MGLOBAL_DATA_FEED(),
            abi.encodeWithSignature("getDataInBase18()"),
            abi.encode(uint256(1_005_764_800_000_000_000))
        );
    }

    function testRunDeploysAndWhitelistsAllCentrifugeAccountsWithoutRegisteringFactories() public {
        vm.recordLogs();
        DeployLiquidLane2Script.LiquidLane2DeploymentData memory data = harness.run();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        DeployLiquidLane2Script.AccountDeploymentData[5] memory deployments;
        deployments[0] = data.jaaa;
        deployments[1] = data.jtrsy;
        deployments[2] = data.hyb;
        deployments[3] = data.deJAAA;
        deployments[4] = data.deJTRSY;

        for (uint256 i; i < deployments.length; ++i) {
            _assertDeployment(deployments[i], i);
        }

        // The OpenEden (HYBOND), Figure (PRIME) and Midas (mGLOBAL) accounts are deployed and
        // whitelisted but not registered, exactly like the Centrifuge ones.
        _assertNonCentrifugeDeployment(data.hybond, harness.HYBOND());
        _assertNonCentrifugeDeployment(data.prime, harness.PRIME());
        _assertNonCentrifugeDeployment(data.mGlobal, harness.MGLOBAL());

        bytes32 whitelistTopic = keccak256("Whitelist(address)");
        bytes32 setAccountFactoryTopic = keccak256("SetAccountFactory(address,address,address)");
        uint256 whitelistEvents;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == whitelistTopic) {
                ++whitelistEvents;
            }
            assertNotEq(logs[i].topics[0], setAccountFactoryTopic);
        }
        // 5 Centrifuge + HYBOND + PRIME + mGLOBAL.
        assertEq(whitelistEvents, deployments.length + 3);
    }

    function _assertNonCentrifugeDeployment(DeployLiquidLane2Script.AccountDeploymentData memory data, address token)
        internal
        view
    {
        assertNotEq(data.oracle, address(0));
        assertNotEq(data.factory, address(0));
        assertNotEq(data.implementation, address(0));
        assertEq(Ownable(data.factory).owner(), harness.FACTORIES_OWNER());
        assertEq(MigratablesFactory(data.factory).implementation(1), data.implementation);
        assertEq(IMigratableEntity(data.implementation).FACTORY(), data.factory);
        assertEq(IAccount(data.implementation).ORACLE(), data.oracle);
        assertEq(IAccount(data.implementation).TOKEN_TO_REDEEM(), token);
    }

    function _assertDeployment(DeployLiquidLane2Script.AccountDeploymentData memory data, uint256 index) internal view {
        MigratablesFactory factory = MigratablesFactory(data.factory);
        AsyncRedeemOracle oracle = AsyncRedeemOracle(data.oracle);
        IAccount account = IAccount(data.implementation);

        assertNotEq(data.oracle, address(0));
        assertNotEq(data.factory, address(0));
        assertNotEq(data.implementation, address(0));
        assertEq(Ownable(data.factory).owner(), harness.FACTORIES_OWNER());
        assertEq(factory.lastVersion(), 1);
        assertEq(factory.implementation(1), data.implementation);
        assertEq(IMigratableEntity(data.implementation).FACTORY(), data.factory);
        assertEq(account.ORACLE(), data.oracle);
        assertEq(account.TOKEN_TO_REDEEM(), tokens[index]);
        assertEq(IAsyncRedeemAccount(data.implementation).REDEMPTION_TOKEN(), harness.USDC());
        assertEq(CentrifugeAccount(data.implementation).ASYNC_REDEEM_VAULT(), asyncRedeemVaults[index]);
        assertEq(ICooldownAccount(data.implementation).COOLDOWN(), 0);
        assertEq(ICoWSwapConverter(data.implementation).COW_SWAP_SETTLEMENT(), harness.COW_SWAP_SETTLEMENT());
        assertEq(oracle.ASYNC_REDEEM_VAULT(), asyncRedeemVaults[index]);
        assertEq(oracle.MIN_PRICE(), minPrices[index]);
        assertEq(oracle.MAX_PRICE(), maxPrices[index]);
        assertEq(oracle.getPrice(), referencePrices[index]);
    }
}
