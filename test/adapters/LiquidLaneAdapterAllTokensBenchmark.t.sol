// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @dev Mainnet-fork benchmark: requires `ETH_RPC_URL` (skipped otherwise; only the pure spec
///      test runs without it). Last updated for the infiniFi locked iUSD change: liUSD-4w/13w
///      seed one unwinding position per second (positions are keyed by the block timestamp), and
///      their wait durations model the next-epoch start plus 4/13 weekly unwinding epochs.
///      Previously updated for the cutoff-based redemptions change: the local constant oracle
///      now exposes `getPriceData()` (required by the ACRED/USCC/bEQTY settlement accounts), and
///      the bEQTY/mGLOBAL/ACRED wait durations model the new cohort/settlement timelines.
///      Re-run on fork after any change to those accounts.
import {Test} from "forge-std/Test.sol";

import {AdapterFactory} from "../../src/contracts/adapters/AdapterFactory.sol";
import {LiquidLaneAdapter} from "../../src/contracts/adapters/LiquidLaneAdapter.sol";
import {AdapterRegistry} from "../../src/contracts/AdapterRegistry.sol";
import {AccountRegistry} from "../../src/contracts/adapters/ll-adapter/AccountRegistry.sol";
import {ACRDX_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/ACRDX_Account.sol";
import {ACRED_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/ACRED_Account.sol";
import {AA_FalconX_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/AA_FalconX_Account.sol";
import {bEQTY_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/bEQTY_Account.sol";
import {
    CarryTradeUSDTRYLeverage_Account
} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/CarryTradeUSDTRYLeverage_Account.sol";
import {DelegatorFactory} from "../../src/contracts/DelegatorFactory.sol";
import {DUSD_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/DUSD_Account.sol";
import {JAAA_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/JAAA_Account.sol";
import {JTRSY_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/JTRSY_Account.sol";
import {PRIME_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/PRIME_Account.sol";
import {
    StockMarketTRBasisTrade_Account
} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/StockMarketTRBasisTrade_Account.sol";
import {deCRDX_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/deCRDX_Account.sol";
import {deJAAA_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/deJAAA_Account.sol";
import {deJTRSY_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/deJTRSY_Account.sol";
import {liUSD13w_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/liUSD13w_Account.sol";
import {liUSD4w_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/liUSD4w_Account.sol";
import {mAPOLLO_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mAPOLLO_Account.sol";
import {mBASIS_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mBASIS_Account.sol";
import {mBTC_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mBTC_Account.sol";
import {mEDGE_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mEDGE_Account.sol";
import {mEVUSD_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mEVUSD_Account.sol";
import {mFARM_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mFARM_Account.sol";
import {mFONE_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mFONE_Account.sol";
import {mGLOBAL_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mGLOBAL_Account.sol";
import {mHYPER_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mHYPER_Account.sol";
import {mHyperBTC_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mHyperBTC_Account.sol";
import {mHyperETH_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mHyperETH_Account.sol";
import {mM1USD_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mM1USD_Account.sol";
import {mMEV_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mMEV_Account.sol";
import {mROX_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mROX_Account.sol";
import {mRe7BTC_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mRe7BTC_Account.sol";
import {mRe7YIELD_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mRe7YIELD_Account.sol";
import {mSL_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mSL_Account.sol";
import {mTBILL_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mTBILL_Account.sol";
import {mevBTC_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mevBTC_Account.sol";
import {msyrupUSD_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/msyrupUSD_Account.sol";
import {msyrupUSDp_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/msyrupUSDp_Account.sol";
import {sAID_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/sAID_Account.sol";
import {sUSN_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/sUSN_Account.sol";
import {sUSD3_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/sUSD3_Account.sol";
import {sthUSD_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/sthUSD_Account.sol";
import {USCC_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/USCC_Account.sol";
import {weETH_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/weETH_Account.sol";
import {wstETH_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/wstETH_Account.sol";
import {MigratablesFactory} from "../../src/contracts/common/MigratablesFactory.sol";
import {Registry} from "../../src/contracts/common/Registry.sol";
import {UniversalDelegator} from "../../src/contracts/delegator/UniversalDelegator.sol";
import {ILiquidLaneAdapter, MAX_TOKENS_TO_REDEEM} from "../../src/interfaces/adapters/ILiquidLaneAdapter.sol";
import {IAccount} from "../../src/interfaces/adapters/ll-adapter/IAccount.sol";
import {IAsyncRedeemAccount} from "../../src/interfaces/adapters/ll-adapter/IAsyncRedeemAccount.sol";
import {IDigiFTAccount} from "../../src/interfaces/adapters/ll-adapter/digift/IDigiFTAccount.sol";
import {IEtherFiAccount} from "../../src/interfaces/adapters/ll-adapter/etherfi/IEtherFiAccount.sol";
import {IFigureAccount} from "../../src/interfaces/adapters/ll-adapter/figure/IFigureAccount.sol";
import {IGaibAccount} from "../../src/interfaces/adapters/ll-adapter/gaib/IGaibAccount.sol";
import {IInfiniFiAccount} from "../../src/interfaces/adapters/ll-adapter/infinifi/IInfiniFiAccount.sol";
import {ILidoAccount} from "../../src/interfaces/adapters/ll-adapter/lido/ILidoAccount.sol";
import {IMakinaAccount} from "../../src/interfaces/adapters/ll-adapter/makina/IMakinaAccount.sol";
import {IMidasAccount} from "../../src/interfaces/adapters/ll-adapter/midas/IMidasAccount.sol";
import {IMidasRedemptionVault} from "../../src/interfaces/adapters/ll-adapter/midas/IMidasRedemptionVault.sol";
import {INoonAccount} from "../../src/interfaces/adapters/ll-adapter/noon/INoonAccount.sol";
import {IParetoAccount} from "../../src/interfaces/adapters/ll-adapter/pareto/IParetoAccount.sol";
import {ISecuritizeAccount} from "../../src/interfaces/adapters/ll-adapter/securitize/ISecuritizeAccount.sol";
import {ISuperstateAccount} from "../../src/interfaces/adapters/ll-adapter/superstate/ISuperstateAccount.sol";
import {ISthUSD} from "../../src/interfaces/adapters/ll-adapter/theo/ISthUSD.sol";
import {IThreeJaneSUSD3} from "../../src/interfaces/adapters/ll-adapter/threejane/IThreeJaneSUSD3.sol";
import {IUniversalDelegator, MAX_SHARE} from "../../src/interfaces/delegator/IUniversalDelegator.sol";
import {IMakinaRedeemer} from "../../src/interfaces/adapters/ll-adapter/makina/IMakinaRedeemer.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract LiquidLaneAdapterAllTokensBenchmarkTest is Test {
    using Math for uint256;

    address internal constant MAINNET_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant COW_SWAP_SETTLEMENT = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;
    address internal constant COW_SWAP_VAULT_RELAYER = 0xC92E8bdf79f0507f65a392b0ab4667716BFE0110;

    address internal constant PRIME_TOKEN = 0x19ebb35279A16207Ec4ba82799CC64715065F7F6;
    address internal constant EETH = 0x35fA164735182de50811E8e2E824cFb9B6118ac2;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant WEETH = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    address internal constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address internal constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address internal constant LIDO_WITHDRAWAL_QUEUE = 0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1;
    address internal constant ETHERFI_LIQUIDITY_POOL = 0x308861A430be4cce5502d0A12724771Fc6DaF216;
    address internal constant ETHERFI_REDEMPTION_MANAGER = 0xE3F384Dc7002547Dd240AC1Ad69a430CCE1e292d;
    address internal constant ETHERFI_WITHDRAW_REQUEST_NFT = 0x7d5706f6ef3F89B3951E23e557CDFBC3239D4E2c;
    address internal constant CENTRIFUGE_HOOK_WARD_1 = 0x7Ed48C31f2fdC40d37407cBaBf0870B2b688368f;
    address internal constant CENTRIFUGE_HOOK_WARD_2 = 0xEC3582fcDc34078a4B7a8c75a5a3AE46f48525aB;
    address internal constant MIDAS_ACCESS_CONTROL_ADMIN = 0xd4195CF4df289a4748C1A7B6dDBE770e27bA1227;
    address internal constant MIDAS_GREENLIST_ADMIN = 0xb5CcD8dC8082467849eE008d4242f7b3b569EF05;
    uint256 internal constant SUPERSTATE_BENCHMARK_ENTITY_ID = 2_026_061_101;

    address internal curator = makeAddr("curator");
    address internal pauser = makeAddr("pauser");
    address internal unpauser = makeAddr("unpauser");

    BenchmarkVaultRegistry internal vaultFactory;
    AdapterFactory internal adapterFactory;
    AdapterRegistry internal adapterRegistry;
    AccountRegistry internal accountRegistry;
    DelegatorFactory internal delegatorFactory;
    BenchmarkLiquidLaneVault internal vault;
    UniversalDelegator internal delegator;
    LiquidLaneAdapter internal adapter;

    struct TokenBenchSpec {
        string symbol;
        uint48 maxDelay;
        uint48 cooldown;
        uint256 maxAverageRequests;
    }

    struct AccountGasBench {
        uint256 totalAssetsGas;
        uint256 syncGas;
        uint256 seededRequests;
        bool syncSuccess;
        bool totalAssetsSuccess;
    }

    struct AggregateGasBench {
        uint256 adapterTotalAssetsGas;
        uint256 delegatorTotalAssetsGas;
        bool adapterTotalAssetsSuccess;
        bool delegatorTotalAssetsSuccess;
    }

    function testCalculatesAllTokenCooldownsAndRequestCounts() public pure {
        TokenBenchSpec[] memory specs = _tokenBenchSpecs();

        assertEq(specs.length, 43);
        assertLe(specs.length, MAX_TOKENS_TO_REDEEM);

        uint256 totalMaxAverageRequests;
        for (uint256 i; i < specs.length; ++i) {
            uint48 expectedCooldown = _cooldown(specs[i].symbol, specs[i].maxDelay);
            assertEq(specs[i].cooldown, expectedCooldown, specs[i].symbol);
            assertEq(
                specs[i].maxAverageRequests, _maxAverageRequests(specs[i].maxDelay, expectedCooldown), specs[i].symbol
            );
            totalMaxAverageRequests += specs[i].maxAverageRequests;
        }
        assertEq(totalMaxAverageRequests, 295);
    }

    function testBenchmarkOnboardsAllTokensToLiquidLaneAdapter() public {
        string memory rpcUrl = vm.envOr("ETH_RPC_URL", string(""));
        _skipWithoutRpc(rpcUrl, "ETH_RPC_URL is required for all-token LiquidLaneAdapter onboarding benchmark");

        vm.pauseGasMetering();
        vm.createSelectFork(rpcUrl);
        _setUpAdapter();

        TokenBenchSpec[] memory specs = _tokenBenchSpecs();
        address[] memory tokens = _registerTokenFactories(specs);

        vm.resumeGasMetering();
        uint256 gasBefore = gasleft();
        _onboardTokens(tokens);
        uint256 onboardingGas = gasBefore - gasleft();

        vm.pauseGasMetering();
        assertEq(adapter.getTokensToRedeemLength(), specs.length);
        _logBench(specs, onboardingGas);
    }

    function testBenchmarkTotalAssetsAndSyncForEachAccount() public {
        string memory rpcUrl = vm.envOr("ETH_RPC_URL", string(""));
        _skipWithoutRpc(rpcUrl, "ETH_RPC_URL is required for account totalAssets/sync benchmark");

        vm.pauseGasMetering();
        vm.createSelectFork(rpcUrl);
        _setUpAdapter();

        TokenBenchSpec[] memory specs = _tokenBenchSpecs();
        address[] memory tokens = _registerTokenFactories(specs);

        _onboardTokens(tokens);

        AccountGasBench[] memory benches = _benchmarkAccountGas(specs, tokens);
        AggregateGasBench memory aggregateBench = _benchmarkAggregateGas();

        assertEq(benches.length, specs.length);
        for (uint256 i; i < benches.length; ++i) {
            uint256 targetRequests = _seedTarget(i, specs[i]);
            assertGt(benches[i].totalAssetsGas, 0, specs[i].symbol);
            assertGt(benches[i].syncGas, 0, specs[i].symbol);
            assertEq(benches[i].seededRequests, targetRequests, specs[i].symbol);
        }

        assertGt(aggregateBench.adapterTotalAssetsGas, 0);
        assertGt(aggregateBench.delegatorTotalAssetsGas, 0);
    }

    function testSeedsMaxRealRequestsForEachAccount() public {
        string memory rpcUrl = vm.envOr("ETH_RPC_URL", string(""));
        _skipWithoutRpc(rpcUrl, "ETH_RPC_URL is required for exact max-request seeding benchmark");

        vm.pauseGasMetering();
        vm.createSelectFork(rpcUrl);
        _setUpAdapter();

        TokenBenchSpec[] memory specs = _tokenBenchSpecs();
        address[] memory tokens = _registerTokenFactories(specs);

        _onboardTokens(tokens);

        for (uint256 i; i < specs.length; ++i) {
            address account = adapter.accounts(tokens[i]);
            uint256 seededRequests = _seedRequests(i, specs[i], tokens[i], account);
            uint256 targetRequests = _seedTarget(i, specs[i]);

            emit log_named_string("token", specs[i].symbol);
            emit log_named_uint("target requests", targetRequests);
            emit log_named_uint("seeded requests", seededRequests);

            assertEq(seededRequests, targetRequests, specs[i].symbol);
        }
    }

    function _setUpAdapter() internal {
        vaultFactory = new BenchmarkVaultRegistry();
        vault = new BenchmarkLiquidLaneVault(MAINNET_USDC);
        vaultFactory.add(address(vault));

        adapterFactory = new AdapterFactory(curator);
        adapterRegistry = new AdapterRegistry(curator);
        accountRegistry = new AccountRegistry(curator);
        delegatorFactory = new DelegatorFactory(curator);

        LiquidLaneAdapter implementation =
            new LiquidLaneAdapter(address(vaultFactory), address(adapterFactory), address(accountRegistry));
        UniversalDelegator delegatorImplementation =
            new UniversalDelegator(0, address(vaultFactory), address(adapterRegistry), address(delegatorFactory));

        vm.startPrank(curator);
        adapterFactory.whitelist(address(implementation));
        delegatorFactory.whitelist(address(delegatorImplementation));

        ILiquidLaneAdapter.InitParams memory params =
            ILiquidLaneAdapter.InitParams({pauser: pauser, unpauser: unpauser});
        adapter = LiquidLaneAdapter(adapterFactory.create(1, curator, abi.encode(address(vault), abi.encode(params))));

        IUniversalDelegator.InitParams memory delegatorParams = IUniversalDelegator.InitParams({
            allocateRoleHolder: curator,
            deallocateRoleHolder: curator,
            addAdapterRoleHolder: curator,
            swapAdaptersRoleHolder: curator,
            defaultAdminRoleHolder: curator,
            removeAdapterRoleHolder: curator,
            setAdapterLimitsRoleHolder: curator,
            setAutoAllocateAdaptersRoleHolder: curator
        });
        delegator =
            UniversalDelegator(delegatorFactory.create(0, abi.encode(address(vault), abi.encode(delegatorParams))));
        vault.setDelegator(address(delegator));
        adapterRegistry.setWhitelistedStatus(address(vault), address(adapter), true);
        delegator.addAdapter(address(adapter));
        delegator.setLimits(address(adapter), type(uint256).max, MAX_SHARE);
        vm.stopPrank();
    }

    function _registerTokenFactories(TokenBenchSpec[] memory specs) internal returns (address[] memory tokens) {
        tokens = new address[](specs.length);

        vm.startPrank(curator);
        for (uint256 i; i < specs.length; ++i) {
            MigratablesFactory accountFactory = new MigratablesFactory(curator);
            IAccount implementation = _deployImplementation(i, address(accountFactory));
            address token = implementation.TOKEN_TO_REDEEM();
            address asset = _assetFor(i, token);

            accountFactory.whitelist(address(implementation));
            accountRegistry.setAccountFactory(asset, token, address(accountFactory));
            tokens[i] = token;
        }
        vm.stopPrank();
    }

    function _onboardTokens(address[] memory tokens) internal {
        vm.startPrank(curator);
        for (uint256 i; i < tokens.length; ++i) {
            _mockVaultAsset(_assetFor(i, tokens[i]));
            adapter.addTokenToRedeem(tokens[i]);
        }
        vm.stopPrank();
    }

    function _assetFor(uint256 index, address token) internal view returns (address) {
        if (
            _isMidas(index) || _isCentrifuge(index) || index == 2 || index == 7 || index == 37 || index == 38
                || index == 40 || _isInfiniFi(index)
        ) {
            return MAINNET_USDC;
        }
        if (index == 5) {
            return IERC4626(IERC4626(token).asset()).asset();
        }
        if (index == 35 || index == 36) {
            return WETH;
        }
        return IERC4626(token).asset();
    }

    function _isMidas(uint256 index) internal pure returns (bool) {
        return index == 1 || index == 6 || (index >= 11 && index <= 31);
    }

    function _isCentrifuge(uint256 index) internal pure returns (bool) {
        return index == 0 || index == 3 || index == 4 || (index >= 8 && index <= 10);
    }

    function _isInfiniFi(uint256 index) internal pure returns (bool) {
        return index == 41 || index == 42;
    }

    function _mockVaultAsset(address asset) internal {
        vm.mockCall(address(vault), abi.encodeWithSelector(IERC4626.asset.selector), abi.encode(asset));
    }

    function _benchmarkAccountGas(TokenBenchSpec[] memory specs, address[] memory tokens)
        internal
        returns (AccountGasBench[] memory benches)
    {
        benches = new AccountGasBench[](specs.length);

        uint256 totalTotalAssetsGas;
        uint256 totalSyncGas;

        for (uint256 i; i < specs.length; ++i) {
            address account = adapter.accounts(tokens[i]);
            assertGt(account.code.length, 0, specs[i].symbol);

            uint256 seededRequests = _seedRequests(i, specs[i], tokens[i], account);

            uint256 totalAssetsGas;
            uint256 syncGas;
            uint256 assets;
            bool syncSuccess;
            bool totalAssetsSuccess;

            {
                vm.resumeGasMetering();
                uint256 gasBefore = gasleft();
                (bool success, bytes memory data) =
                    account.staticcall(abi.encodeWithSelector(IAccount.totalAssets.selector));
                totalAssetsGas = gasBefore - gasleft();
                totalAssetsSuccess = success;
                assets = success ? abi.decode(data, (uint256)) : 0;

                gasBefore = gasleft();
                (syncSuccess,) = account.call(abi.encodeWithSelector(IAccount.sync.selector));
                syncGas = gasBefore - gasleft();
                vm.pauseGasMetering();
            }

            benches[i] = AccountGasBench({
                totalAssetsGas: totalAssetsGas,
                syncGas: syncGas,
                seededRequests: seededRequests,
                syncSuccess: syncSuccess,
                totalAssetsSuccess: totalAssetsSuccess
            });
            totalTotalAssetsGas += totalAssetsGas;
            totalSyncGas += syncGas;

            emit log_named_string("token", specs[i].symbol);
            emit log_named_address("account", account);
            emit log_named_uint("target requests", _seedTarget(i, specs[i]));
            emit log_named_uint("seeded requests", seededRequests);
            emit log_named_uint("totalAssets", assets);
            emit log_named_uint("totalAssets success", totalAssetsSuccess ? 1 : 0);
            emit log_named_uint("totalAssets gas", totalAssetsGas);
            emit log_named_uint("sync success", syncSuccess ? 1 : 0);
            emit log_named_uint("sync gas", syncGas);
        }

        emit log_named_uint("accounts benchmarked", specs.length);
        emit log_named_uint("total totalAssets gas", totalTotalAssetsGas);
        emit log_named_uint("total sync gas", totalSyncGas);
    }

    function _benchmarkAggregateGas() internal returns (AggregateGasBench memory bench) {
        vm.resumeGasMetering();
        uint256 gasBefore = gasleft();
        (bool adapterTotalAssetsSuccess,) =
            address(adapter).staticcall(abi.encodeWithSelector(LiquidLaneAdapter.totalAssets.selector));
        uint256 adapterTotalAssetsGas = gasBefore - gasleft();

        gasBefore = gasleft();
        (bool delegatorTotalAssetsSuccess,) =
            address(delegator).staticcall(abi.encodeWithSelector(UniversalDelegator.totalAssets.selector));
        uint256 delegatorTotalAssetsGas = gasBefore - gasleft();
        vm.pauseGasMetering();

        bench = AggregateGasBench({
            adapterTotalAssetsGas: adapterTotalAssetsGas,
            delegatorTotalAssetsGas: delegatorTotalAssetsGas,
            adapterTotalAssetsSuccess: adapterTotalAssetsSuccess,
            delegatorTotalAssetsSuccess: delegatorTotalAssetsSuccess
        });

        emit log_named_uint("adapter totalAssets success", adapterTotalAssetsSuccess ? 1 : 0);
        emit log_named_uint("adapter totalAssets gas", adapterTotalAssetsGas);
        emit log_named_uint("delegator totalAssets success", delegatorTotalAssetsSuccess ? 1 : 0);
        emit log_named_uint("delegator totalAssets gas", delegatorTotalAssetsGas);
    }

    function _seedRequests(uint256 index, TokenBenchSpec memory spec, address token, address account)
        internal
        returns (uint256 seeded)
    {
        uint256 targetRequests = _seedTarget(index, spec);
        uint256 requestsBefore = _requestUnits(index, token, account);
        for (uint256 i; seeded < targetRequests && i < targetRequests; ++i) {
            _fundRequest(index, token, account);

            vm.prank(curator);
            (bool success, bytes memory reason) = account.call(abi.encodeWithSelector(IAccount.sync.selector));
            if (!success) {
                emit log_named_bytes("sync revert", reason);
                emit log_named_uint("token balance", IERC20(token).balanceOf(account));
                deal(token, account, 0);
                return seeded;
            }

            uint256 requestsAfter = _requestUnits(index, token, account);
            if (requestsAfter <= requestsBefore) {
                return seeded;
            }

            seeded += requestsAfter - requestsBefore;
            requestsBefore = requestsAfter;
        }
    }

    function _seedTarget(uint256 index, TokenBenchSpec memory spec) internal pure returns (uint256) {
        if (index == 33 || index == 34 || index == 37) {
            return 1;
        }
        return spec.maxAverageRequests;
    }

    function _fundRequest(uint256 index, address token, address account) internal {
        uint256 amount = _requestAmount(index, token);
        if (_isCentrifuge(index)) {
            _permissionCentrifugeMember(token, account);
            _dealCentrifugeShare(token, account, amount);
            return;
        }
        if (_isMidas(index)) {
            _configureMidasRequestPath(index, token, account);
        }
        if (index == 2) {
            _whitelistMakinaRedeemer(account);
        }
        if (index == 7) {
            _permissionDigiFTTransfer(token, account);
        }
        if (index == 37) {
            _configureParetoRequestPath(account);
        }
        if (index == 38) {
            _fundSecuritizeRequest(token, account, amount);
            return;
        }
        if (index == 40) {
            _fundSuperstateRequest(token, account, amount);
            return;
        }
        if (_isInfiniFi(index)) {
            // infiniFi unwinding positions are keyed by keccak(account, block.timestamp), so each
            // seeded request needs its own second
            vm.warp(vm.getBlockTimestamp() + 1);
            deal(token, account, amount);
            return;
        }
        if (index != 35 && index != 36 && _tryMintERC4626Shares(token, account, amount)) {
            return;
        }

        deal(token, account, amount);
    }

    function _whitelistMakinaRedeemer(address account) internal {
        address redeemer = IMakinaAccount(account).REDEEMER();
        if (!IMakinaWhitelist(redeemer).isWhitelistEnabled() || IMakinaWhitelist(redeemer).isWhitelistedUser(account)) {
            return;
        }

        address[] memory users = new address[](1);
        users[0] = account;
        vm.prank(IMakinaMachineGovernance(IMakinaRedeemer(redeemer).machine()).riskManager());
        IMakinaWhitelist(redeemer).setWhitelistedUsers(users, true);
    }

    function _dealCentrifugeShare(address token, address account, uint256 amount) internal {
        vm.record();
        IERC20(token).balanceOf(account);
        (bytes32[] memory reads,) = vm.accesses(token);

        bytes32 balanceSlot = reads[0];
        bytes32 packedBalance = vm.load(token, balanceSlot);
        vm.store(token, balanceSlot, bytes32((uint256(packedBalance) & ~uint256(type(uint128).max)) | amount));
    }

    function _permissionCentrifugeMember(address token, address account) internal {
        address hook = ICentrifugeShareToken(token).hook();
        bytes memory callData =
            abi.encodeWithSelector(ICentrifugeTransferHook.updateMember.selector, token, account, type(uint64).max);

        vm.prank(CENTRIFUGE_HOOK_WARD_1);
        (bool success, bytes memory reason) = hook.call(callData);
        if (success) {
            return;
        }

        vm.prank(CENTRIFUGE_HOOK_WARD_2);
        (success, reason) = hook.call(callData);
        if (!success) {
            emit log_named_bytes("centrifuge permission revert", reason);
        }
    }

    function _configureMidasRequestPath(uint256 index, address token, address account) internal {
        address asset = _assetFor(index, token);
        address redemptionVault = IMidasAccount(account).REDEMPTION_VAULT();
        address accessControl = IMidasVaultAdmin(redemptionVault).accessControl();

        if (IMidasVaultAdmin(redemptionVault).greenlistEnabled()) {
            bytes32 greenlistedRole = IMidasVaultAdmin(redemptionVault).greenlistedRole();
            _grantMidasRole(accessControl, greenlistedRole, account);
        }

        bytes32 pauseAdminRole = IMidasVaultAdmin(redemptionVault).pauseAdminRole();
        if (IMidasVaultAdmin(redemptionVault).paused()) {
            _grantMidasRole(accessControl, pauseAdminRole, curator);

            vm.prank(curator);
            IMidasVaultAdmin(redemptionVault).unpause();
        }

        bytes4 redeemRequestSelector = IMidasRedemptionVault.redeemRequest.selector;
        if (IMidasVaultAdmin(redemptionVault).fnPaused(redeemRequestSelector)) {
            _grantMidasRole(accessControl, pauseAdminRole, curator);

            vm.prank(curator);
            IMidasVaultAdmin(redemptionVault).unpauseFn(redeemRequestSelector);
        }

        address mTokenDataFeed = IMidasVaultAdmin(redemptionVault).mTokenDataFeed();
        _stabilizeMidasDataFeed(mTokenDataFeed);

        (address dataFeed, uint256 fee, uint256 allowance, bool stable) =
            IMidasRedemptionVault(redemptionVault).tokensConfig(asset);
        if (dataFeed > address(0)) {
            if (stable && dataFeed != mTokenDataFeed) {
                bytes32 vaultRole = IMidasVaultAdmin(redemptionVault).vaultRole();
                _grantMidasRole(accessControl, vaultRole, curator);

                vm.startPrank(curator, curator);
                IMidasVaultAdmin(redemptionVault).removePaymentToken(asset);
                IMidasVaultAdmin(redemptionVault).addPaymentToken(asset, mTokenDataFeed, fee, allowance, stable);
                vm.stopPrank();

                dataFeed = mTokenDataFeed;
            }

            _stabilizeMidasDataFeed(dataFeed);
            return;
        }

        bytes32 vaultRole = IMidasVaultAdmin(redemptionVault).vaultRole();
        _grantMidasRole(accessControl, vaultRole, curator);

        vm.startPrank(curator, curator);
        IMidasVaultAdmin(redemptionVault).addPaymentToken(asset, mTokenDataFeed, 0, type(uint256).max, true);
        vm.stopPrank();
    }

    function _stabilizeMidasDataFeed(address dataFeed) internal {
        (bool success,) = dataFeed.staticcall(abi.encodeWithSelector(IMidasDataFeed.getDataInBase18.selector));
        if (success) {
            return;
        }

        (,,, uint256 updatedAt,) = IChainlinkAggregatorV3(IMidasDataFeed(dataFeed).aggregator()).latestRoundData();
        vm.warp(updatedAt + IMidasDataFeed(dataFeed).healthyDiff() / 2);
    }

    function _grantMidasRole(address accessControl, bytes32 role, address account) internal {
        if (IMidasAccessControl(accessControl).hasRole(role, account)) {
            return;
        }

        bytes32 adminRole = IMidasAccessControl(accessControl).getRoleAdmin(role);
        address admin = MIDAS_ACCESS_CONTROL_ADMIN;
        if (!IMidasAccessControl(accessControl).hasRole(adminRole, admin)) {
            admin = MIDAS_GREENLIST_ADMIN;
        }
        assertTrue(IMidasAccessControl(accessControl).hasRole(adminRole, admin));

        vm.prank(admin);
        IMidasAccessControl(accessControl).grantRole(role, account);
    }

    function _permissionDigiFTTransfer(address token, address account) internal {
        address management = IDigiFTSecurityToken(token).management();
        address subAccount = vm.computeCreateAddress(account, vm.getNonce(account));

        _storeObservedBool(
            management, abi.encodeWithSelector(IDigiFTManagement.isWhiteContract.selector, account), true
        );
        _storeObservedBool(
            management, abi.encodeWithSelector(IDigiFTManagement.isWhiteInvestor.selector, subAccount), true
        );
    }

    function _storeObservedBool(address target, bytes memory callData, bool value) internal {
        vm.record();
        (bool success,) = target.staticcall(callData);
        assertTrue(success);
        (bytes32[] memory reads,) = vm.accesses(target);

        assertGt(reads.length, 0);
        vm.store(target, reads[reads.length - 1], bytes32(uint256(value ? 1 : 0)));
    }

    function _configureParetoRequestPath(address account) internal {
        address idleCdo = IParetoAccount(account).IDLE_CDO();
        address owner = IOwnable(idleCdo).owner();

        vm.prank(owner);
        IParetoEpochVault(idleCdo).restoreOperations();

        if (!IParetoEpochVault(idleCdo).isWalletAllowed(account)) {
            vm.prank(owner);
            IParetoEpochVault(idleCdo).setKeyringParams(address(0), 0, true);
        }
    }

    function _fundSecuritizeRequest(address token, address account, uint256 amount) internal {
        address registry = IDSServiceConsumer(token).getDSService(4);
        address trustService = IDSServiceConsumer(token).getDSService(1);
        address owner = IOwnable(registry).owner();
        address nextSubAccount = vm.computeCreateAddress(account, vm.getNonce(account));
        string memory investorId = "liquid-lane-benchmark";

        if (!IDSRegistryService(registry).isInvestor(investorId)) {
            vm.prank(owner);
            IDSRegistryService(registry).registerInvestor(investorId, "");
        }

        _registerSecuritizeWallet(registry, owner, account, investorId);
        _registerSecuritizeWallet(registry, owner, nextSubAccount, investorId);

        vm.prank(owner);
        IDSTrustService(trustService).setRole(nextSubAccount, 8);

        vm.prank(owner);
        IDSecuritizeToken(token).issueTokens(account, amount);
    }

    function _registerSecuritizeWallet(address registry, address owner, address wallet, string memory investorId)
        internal
    {
        if (IDSRegistryService(registry).isWallet(wallet)) {
            return;
        }

        vm.prank(owner);
        IDSRegistryService(registry).addWallet(wallet, investorId);
    }

    function _fundSuperstateRequest(address token, address account, uint256 amount) internal {
        address allowlist = ISuperstateLiveToken(token).allowlistV2();
        address subAccount = vm.computeCreateAddress(account, vm.getNonce(account));

        _allowSuperstateAddress(allowlist, account);
        _allowSuperstateAddress(allowlist, subAccount);

        vm.prank(IOwnable(token).owner());
        ISuperstateLiveToken(token).mint(account, amount);
    }

    function _allowSuperstateAddress(address allowlist, address account) internal {
        if (ISuperstateAllowlist(allowlist).addressEntityIds(account) == SUPERSTATE_BENCHMARK_ENTITY_ID) {
            return;
        }

        address owner = IOwnable(allowlist).owner();
        if (ISuperstateAllowlist(allowlist).isEntityAllowedForPrivateInstrument(SUPERSTATE_BENCHMARK_ENTITY_ID, "USCC"))
        {
            vm.prank(owner);
            ISuperstateAllowlist(allowlist).setEntityIdForAddress(SUPERSTATE_BENCHMARK_ENTITY_ID, account);
            return;
        }

        string[] memory fundSymbols = new string[](1);
        bool[] memory permissions = new bool[](1);
        address[] memory accounts = new address[](1);

        accounts[0] = account;
        fundSymbols[0] = "USCC";
        permissions[0] = true;

        vm.prank(owner);
        ISuperstateAllowlist(allowlist)
            .setEntityPermissionsAndAddresses(SUPERSTATE_BENCHMARK_ENTITY_ID, accounts, fundSymbols, permissions);
    }

    function _tryMintERC4626Shares(address token, address account, uint256 shares) internal returns (bool) {
        try IERC4626(token).asset() returns (address asset) {
            if (asset == address(0) || asset.code.length == 0) {
                return false;
            }

            uint256 assets;
            try IERC4626(token).previewMint(shares) returns (uint256 previewAssets) {
                assets = previewAssets;
            } catch {
                return false;
            }
            if (assets == 0) {
                return false;
            }

            deal(asset, account, IERC20(asset).balanceOf(account) + assets);
            vm.prank(account);
            (bool approveSuccess,) = asset.call(abi.encodeWithSelector(IERC20.approve.selector, token, assets));
            if (!approveSuccess) {
                return false;
            }

            vm.prank(account);
            (bool mintSuccess,) = token.call(abi.encodeWithSelector(IERC4626.mint.selector, shares, account));
            return mintSuccess;
        } catch {
            return false;
        }
    }

    function _requestAmount(uint256 index, address token) internal view returns (uint256) {
        if (index == 35 || index == 36) {
            return 1 ether;
        }

        uint256 unit = 10 ** IERC20Metadata(token).decimals();
        if (_isMidas(index) || _isCentrifuge(index) || index == 2 || index == 5 || index == 37 || index == 39) {
            return 100 * unit;
        }

        return unit;
    }

    function _requestUnits(uint256 index, address token, address account) internal view returns (uint256) {
        if (_isMidas(index)) {
            return _midasRequestIdsLength(account);
        }
        if (_isCentrifuge(index)) {
            return _asyncRequestIdsLength(account);
        }
        if (index == 5) {
            return IFigureAccount(account).pendingAssets() > 0 ? 1 : 0;
        }
        if (index == 2) {
            return _makinaRequestIdsLength(account);
        }
        if (index == 7) {
            return _digiFTSubAccountsLength(account);
        }
        if (index == 32) {
            return _gaibSubAccountsLength(account);
        }
        if (index == 33) {
            (,, uint256 shares) = IThreeJaneSUSD3(token).getCooldownStatus(account);
            return shares > 0 ? 1 : 0;
        }
        if (index == 34) {
            (, uint256 shares,) = ISthUSD(token).currentRedeemRequest(account);
            return shares > 0 ? 1 : 0;
        }
        if (index == 35) {
            return _etherFiRequestIdsLength(account);
        }
        if (index == 36) {
            return _lidoRequestIdsLength(account);
        }
        if (index == 37) {
            return IERC20(IParetoAccount(account).RECEIPT_TOKEN()).balanceOf(account) > 0 ? 1 : 0;
        }
        if (index == 38) {
            return _securitizeSubAccountsLength(account);
        }
        if (index == 39) {
            return _noonRequestIdsLength(account);
        }
        if (index == 40) {
            return _superstateSubAccountsLength(account);
        }
        if (_isInfiniFi(index)) {
            return _infiniFiUnwindingTimestampsLength(account);
        }
        return 0;
    }

    function _midasRequestIdsLength(address account) internal view returns (uint256 length) {
        while (true) {
            try IMidasAccount(account).requestIds(length) returns (uint64) {
                ++length;
            } catch {
                return length;
            }
        }
    }

    function _asyncRequestIdsLength(address account) internal view returns (uint256 length) {
        while (true) {
            try IAsyncRedeemAccount(account).requestIds(length) returns (uint64) {
                ++length;
            } catch {
                return length;
            }
        }
    }

    function _makinaRequestIdsLength(address account) internal view returns (uint256 length) {
        while (true) {
            try IMakinaAccount(account).requestIds(length) returns (uint64) {
                ++length;
            } catch {
                return length;
            }
        }
    }

    function _etherFiRequestIdsLength(address account) internal view returns (uint256 length) {
        while (true) {
            try IEtherFiAccount(payable(account)).requestIds(length) returns (uint64) {
                ++length;
            } catch {
                return length;
            }
        }
    }

    function _lidoRequestIdsLength(address account) internal view returns (uint256 length) {
        while (true) {
            try ILidoAccount(payable(account)).requestIds(length) returns (uint64) {
                ++length;
            } catch {
                return length;
            }
        }
    }

    function _infiniFiUnwindingTimestampsLength(address account) internal view returns (uint256 length) {
        while (true) {
            try IInfiniFiAccount(account).unwindingTimestamps(length) returns (uint48) {
                ++length;
            } catch {
                return length;
            }
        }
    }

    function _noonRequestIdsLength(address account) internal view returns (uint256 length) {
        while (true) {
            try INoonAccount(account).requestIds(length) returns (uint256) {
                ++length;
            } catch {
                return length;
            }
        }
    }

    function _digiFTSubAccountsLength(address account) internal view returns (uint256 length) {
        while (true) {
            try IDigiFTAccount(account).subAccounts(length) returns (address) {
                ++length;
            } catch {
                return length;
            }
        }
    }

    function _gaibSubAccountsLength(address account) internal view returns (uint256 length) {
        while (true) {
            try IGaibAccount(account).subAccounts(length) returns (address) {
                ++length;
            } catch {
                return length;
            }
        }
    }

    function _securitizeSubAccountsLength(address account) internal view returns (uint256 length) {
        while (true) {
            try ISecuritizeAccount(account).subAccounts(length) returns (address) {
                ++length;
            } catch {
                return length;
            }
        }
    }

    function _superstateSubAccountsLength(address account) internal view returns (uint256 length) {
        while (true) {
            try ISuperstateAccount(account).subAccounts(length) returns (address) {
                ++length;
            } catch {
                return length;
            }
        }
    }

    function _tokenBenchSpecs() internal pure returns (TokenBenchSpec[] memory specs) {
        specs = new TokenBenchSpec[](43);
        specs[0] = _spec("ACRDX", 1 days);
        specs[1] = _spec("CarryTradeUSDTRYLeverage", 2 days);
        specs[2] = _spec("DUSD", 12 hours);
        specs[3] = _spec("JAAA", 1 days);
        specs[4] = _spec("JTRSY", 1 days);
        specs[5] = _spec("PRIME", 1 days);
        specs[6] = _spec("StockMarketTRBasisTrade", 2 days);
        // bEQTY settles through DigiFT subaccounts with a 7-day write-off duration.
        specs[7] = _spec("bEQTY", 7 days);
        specs[8] = _spec("deCRDX", 1 days);
        specs[9] = _spec("deJAAA", 1 days);
        specs[10] = _spec("deJTRSY", 1 days);
        specs[11] = _spec("mAPOLLO", 3 days);
        specs[12] = _spec("mBASIS", 7 days);
        specs[13] = _spec("mBTC", 7 days);
        specs[14] = _spec("mEDGE", 3 days);
        specs[15] = _spec("mEVUSD", 3 days);
        specs[16] = _spec("mFARM", 7 days);
        specs[17] = _spec("mFONE", 35 days);
        // mGLOBAL cohort worst case: 30-day wait to cutoff + 5-day valuation delay + 45-day settlement.
        specs[18] = _spec("mGLOBAL", 80 days);
        specs[19] = _spec("mHYPER", 3 days);
        specs[20] = _spec("mHyperBTC", 7 days);
        specs[21] = _spec("mHyperETH", 7 days);
        specs[22] = _spec("mM1USD", 17 days);
        specs[23] = _spec("mMEV", 3 days);
        specs[24] = _spec("mROX", 3 days);
        specs[25] = _spec("mRe7BTC", 24 days);
        specs[26] = _spec("mRe7YIELD", 24 days);
        specs[27] = _spec("mSL", 3 days);
        specs[28] = _spec("mTBILL", 3 days);
        specs[29] = _spec("mevBTC", 7 days);
        specs[30] = _spec("msyrupUSD", 7 days);
        specs[31] = _spec("msyrupUSDp", 3 days);
        specs[32] = _spec("sAID", 62 days);
        specs[33] = _spec("sUSD3", 30 days);
        specs[34] = _spec("sthUSD", 7 days);
        specs[35] = _spec("weETH", 14 days);
        specs[36] = _spec("wstETH", 5 days);
        specs[37] = _spec("AA_FalconXUSDC", 30 days);
        // ACRED cohort worst case: 91-day wait to cutoff + 4-day valuation delay + 30-day settlement.
        specs[38] = _spec("ACRED", 125 days);
        specs[39] = _spec("sUSN", 7 days);
        specs[40] = _spec("USCC", 3 days);
        // liUSD positions unwind from the next weekly epoch for N epochs: 4w worst case is 35 days
        // wall clock and 13w is 98 days, plus a small margin for withdrawal processing.
        specs[41] = _spec("liUSD-4w", 36 days);
        specs[42] = _spec("liUSD-13w", 100 days);
    }

    function _deployImplementation(uint256 index, address factory) internal returns (IAccount implementation) {
        if (index == 0) {
            return IAccount(address(new ACRDX_Account(_oracle(), factory, COW_SWAP_SETTLEMENT)));
        }
        if (index == 1) {
            return IAccount(address(new CarryTradeUSDTRYLeverage_Account(factory, COW_SWAP_SETTLEMENT)));
        }
        if (index == 2) {
            return IAccount(address(new DUSD_Account(factory, COW_SWAP_SETTLEMENT)));
        }
        if (index == 3) {
            return IAccount(address(new JAAA_Account(_oracle(), factory, COW_SWAP_SETTLEMENT)));
        }
        if (index == 4) {
            return IAccount(address(new JTRSY_Account(_oracle(), factory, COW_SWAP_SETTLEMENT)));
        }
        if (index == 5) {
            return IAccount(address(new PRIME_Account(_oracle(), factory, PRIME_TOKEN, COW_SWAP_SETTLEMENT)));
        }
        if (index == 6) {
            return IAccount(address(new StockMarketTRBasisTrade_Account(factory, COW_SWAP_SETTLEMENT)));
        }
        if (index == 7) {
            return IAccount(address(new bEQTY_Account(_oracle(), factory, COW_SWAP_SETTLEMENT)));
        }
        if (index == 8) {
            return IAccount(address(new deCRDX_Account(_oracle(), factory, COW_SWAP_SETTLEMENT)));
        }
        if (index == 9) {
            return IAccount(address(new deJAAA_Account(_oracle(), factory, COW_SWAP_SETTLEMENT)));
        }
        if (index == 10) {
            return IAccount(address(new deJTRSY_Account(_oracle(), factory, COW_SWAP_SETTLEMENT)));
        }
        if (index == 11) {
            return IAccount(address(new mAPOLLO_Account(factory, COW_SWAP_SETTLEMENT)));
        }
        if (index == 12) {
            return IAccount(address(new mBASIS_Account(factory, COW_SWAP_SETTLEMENT)));
        }
        if (index == 13) {
            return IAccount(address(new mBTC_Account(factory, COW_SWAP_SETTLEMENT)));
        }
        if (index == 14) {
            return IAccount(address(new mEDGE_Account(factory, COW_SWAP_SETTLEMENT)));
        }
        if (index == 15) {
            return IAccount(address(new mEVUSD_Account(factory, COW_SWAP_SETTLEMENT)));
        }
        if (index == 16) {
            return IAccount(address(new mFARM_Account(factory, COW_SWAP_SETTLEMENT)));
        }
        if (index == 17) {
            return IAccount(address(new mFONE_Account(factory, COW_SWAP_SETTLEMENT)));
        }
        if (index == 18) {
            return IAccount(address(new mGLOBAL_Account(factory, COW_SWAP_SETTLEMENT)));
        }
        if (index == 19) {
            return IAccount(address(new mHYPER_Account(factory, COW_SWAP_SETTLEMENT)));
        }
        if (index == 20) {
            return IAccount(address(new mHyperBTC_Account(factory, COW_SWAP_SETTLEMENT)));
        }
        if (index == 21) {
            return IAccount(address(new mHyperETH_Account(factory, COW_SWAP_SETTLEMENT)));
        }
        if (index == 22) {
            return IAccount(address(new mM1USD_Account(factory, COW_SWAP_SETTLEMENT)));
        }
        if (index == 23) {
            return IAccount(address(new mMEV_Account(factory, COW_SWAP_SETTLEMENT)));
        }
        if (index == 24) {
            return IAccount(address(new mROX_Account(factory, COW_SWAP_SETTLEMENT)));
        }
        if (index == 25) {
            return IAccount(address(new mRe7BTC_Account(factory, COW_SWAP_SETTLEMENT)));
        }
        if (index == 26) {
            return IAccount(address(new mRe7YIELD_Account(factory, COW_SWAP_SETTLEMENT)));
        }
        if (index == 27) {
            return IAccount(address(new mSL_Account(factory, COW_SWAP_SETTLEMENT)));
        }
        if (index == 28) {
            return IAccount(address(new mTBILL_Account(factory, COW_SWAP_SETTLEMENT)));
        }
        if (index == 29) {
            return IAccount(address(new mevBTC_Account(factory, COW_SWAP_SETTLEMENT)));
        }
        if (index == 30) {
            return IAccount(address(new msyrupUSD_Account(factory, COW_SWAP_SETTLEMENT)));
        }
        if (index == 31) {
            return IAccount(address(new msyrupUSDp_Account(factory, COW_SWAP_SETTLEMENT)));
        }
        if (index == 32) {
            return IAccount(address(new sAID_Account(factory, COW_SWAP_SETTLEMENT)));
        }
        if (index == 33) {
            return IAccount(address(new sUSD3_Account(_oracle(), factory, COW_SWAP_SETTLEMENT)));
        }
        if (index == 34) {
            return IAccount(address(new sthUSD_Account(_oracle(), factory, COW_SWAP_SETTLEMENT)));
        }
        if (index == 35) {
            return IAccount(
                address(
                    new weETH_Account(
                        EETH,
                        WETH,
                        WEETH,
                        _oracle(),
                        factory,
                        ETHERFI_LIQUIDITY_POOL,
                        ETHERFI_REDEMPTION_MANAGER,
                        COW_SWAP_SETTLEMENT,
                        ETHERFI_WITHDRAW_REQUEST_NFT
                    )
                )
            );
        }
        if (index == 36) {
            return IAccount(
                address(
                    new wstETH_Account(
                        STETH, WETH, _oracle(), WSTETH, factory, LIDO_WITHDRAWAL_QUEUE, COW_SWAP_SETTLEMENT
                    )
                )
            );
        }
        if (index == 37) {
            return IAccount(address(new AA_FalconX_Account(_oracle(), factory, COW_SWAP_SETTLEMENT)));
        }
        if (index == 38) {
            return IAccount(address(new ACRED_Account(_oracle(), factory, COW_SWAP_SETTLEMENT)));
        }
        if (index == 39) {
            return IAccount(address(new sUSN_Account(_oracle(), factory, COW_SWAP_SETTLEMENT)));
        }
        if (index == 40) {
            return IAccount(address(new USCC_Account(_oracle(), factory, COW_SWAP_SETTLEMENT)));
        }
        if (index == 41) {
            return IAccount(address(new liUSD4w_Account(factory, COW_SWAP_SETTLEMENT)));
        }
        if (index == 42) {
            return IAccount(address(new liUSD13w_Account(factory, COW_SWAP_SETTLEMENT)));
        }
        revert();
    }

    function _spec(string memory symbol, uint48 maxDelay) internal pure returns (TokenBenchSpec memory spec) {
        uint48 cooldown = _cooldown(symbol, maxDelay);
        spec = TokenBenchSpec({
            symbol: symbol,
            maxDelay: maxDelay,
            cooldown: cooldown,
            maxAverageRequests: _maxAverageRequests(maxDelay, cooldown)
        });
    }

    function _cooldown(string memory symbol, uint48 maxDelay) internal pure returns (uint48) {
        if (keccak256(bytes(symbol)) == keccak256("mFONE") || keccak256(bytes(symbol)) == keccak256("mGLOBAL")) {
            return 36 hours;
        }

        uint48 cooldown = maxDelay / 10;
        return cooldown < 1 days ? uint48(1 days) : cooldown;
    }

    function _maxAverageRequests(uint48 maxDelay, uint48 cooldown) internal pure returns (uint256) {
        return maxDelay == 0 ? 0 : uint256(maxDelay).ceilDiv(cooldown);
    }

    function _oracle() internal returns (address) {
        return address(new BenchmarkConstantOracle());
    }

    function _logBench(TokenBenchSpec[] memory specs, uint256 onboardingGas) internal {
        uint256 totalMaxAverageRequests;
        emit log_named_uint("tokens onboarded", specs.length);
        emit log_named_uint("all-token onboarding gas", onboardingGas);

        for (uint256 i; i < specs.length; ++i) {
            totalMaxAverageRequests += specs[i].maxAverageRequests;
            emit log_named_string("token", specs[i].symbol);
            emit log_named_uint("maxDelay", specs[i].maxDelay);
            emit log_named_uint("cooldown", specs[i].cooldown);
            emit log_named_uint("maxAverageRequests", specs[i].maxAverageRequests);
        }

        emit log_named_uint("total maxAverageRequests", totalMaxAverageRequests);
    }

    function _skipWithoutRpc(string memory rpcUrl, string memory reason) internal {
        if (bytes(rpcUrl).length == 0) {
            vm.skip(true, reason);
        }
    }
}

contract BenchmarkVaultRegistry is Registry {
    function add(address entity) external {
        _addEntity(entity);
    }
}

contract BenchmarkLiquidLaneVault {
    address public immutable asset;
    address public delegator;

    constructor(address asset_) {
        asset = asset_;
    }

    function setDelegator(address newDelegator) external {
        delegator = newDelegator;
    }

    function freeAssets() external view returns (uint256) {
        return IERC20(asset).balanceOf(address(this));
    }

    function version() external pure returns (uint64) {
        return 3;
    }
}

contract BenchmarkConstantOracle {
    function getPrice() external pure returns (uint256) {
        return 1e18;
    }

    /// @dev Settlement accounts (ACRED/USCC/bEQTY) and other CutoffPricer hosts read
    ///      `getPriceData()` on sync/totalAssets; a fresh `updatedAt` keeps cohort freezing live.
    function getPriceData() external view returns (uint256 price, uint48 updatedAt) {
        return (1e18, uint48(block.timestamp));
    }
}

interface ICentrifugeShareToken {
    function hook() external view returns (address);
}

interface ICentrifugeTransferHook {
    function updateMember(address token, address user, uint64 validUntil) external;
}

interface IDigiFTSecurityToken {
    function management() external view returns (address);
}

interface IDigiFTManagement {
    function isWhiteContract(address contractAddress) external view returns (bool);

    function isWhiteInvestor(address investor) external view returns (bool);
}

interface IParetoEpochVault {
    function isWalletAllowed(address user) external view returns (bool);

    function restoreOperations() external;

    function setKeyringParams(address keyring, uint256 policyId, bool keyringAllowWithdraw) external;
}

interface IOwnable {
    function owner() external view returns (address);
}

interface IDSServiceConsumer {
    function getDSService(uint256 serviceId) external view returns (address);
}

interface IDSRegistryService {
    function addWallet(address wallet, string calldata investorId) external returns (bool);

    function isInvestor(string calldata investorId) external view returns (bool);

    function isWallet(address wallet) external view returns (bool);

    function registerInvestor(string calldata investorId, string calldata collisionHash) external returns (bool);
}

interface IDSecuritizeToken {
    function issueTokens(address account, uint256 amount) external returns (bool);
}

interface IDSTrustService {
    function setRole(address account, uint8 role) external returns (bool);
}

interface ISuperstateLiveToken {
    function allowlistV2() external view returns (address);

    function mint(address account, uint256 amount) external;
}

interface ISuperstateAllowlist {
    function addressEntityIds(address account) external view returns (uint256);

    function isEntityAllowedForPrivateInstrument(uint256 entityId, string calldata instrument)
        external
        view
        returns (bool);

    function setEntityIdForAddress(uint256 entityId, address account) external;

    function setEntityPermissionsAndAddresses(
        uint256 entityId,
        address[] calldata accounts,
        string[] calldata fundSymbols,
        bool[] calldata permissions
    ) external;
}

interface IMidasAccessControl {
    function getRoleAdmin(bytes32 role) external view returns (bytes32);

    function hasRole(bytes32 role, address account) external view returns (bool);

    function grantRole(bytes32 role, address account) external;
}

interface IMidasDataFeed {
    function aggregator() external view returns (address);

    function getDataInBase18() external view returns (uint256);

    function healthyDiff() external view returns (uint256);
}

interface IMidasVaultAdmin {
    function accessControl() external view returns (address);

    function addPaymentToken(address token, address dataFeed, uint256 tokenFee, uint256 allowance, bool stable) external;

    function fnPaused(bytes4 selector) external view returns (bool);

    function greenlistEnabled() external view returns (bool);

    function greenlistedRole() external view returns (bytes32);

    function mTokenDataFeed() external view returns (address);

    function pauseAdminRole() external view returns (bytes32);

    function paused() external view returns (bool);

    function removePaymentToken(address token) external;

    function unpause() external;

    function unpauseFn(bytes4 selector) external;

    function vaultRole() external view returns (bytes32);
}

interface IChainlinkAggregatorV3 {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

interface IMakinaMachineGovernance {
    function riskManager() external view returns (address);
}

interface IMakinaWhitelist {
    function isWhitelistEnabled() external view returns (bool);

    function isWhitelistedUser(address user) external view returns (bool);

    function setWhitelistedUsers(address[] calldata users, bool whitelisted) external;
}
