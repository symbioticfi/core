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
import {MGlobalDataFeedHelper} from "../helpers/MGlobalDataFeedHelper.sol";

import {AdapterFactory} from "../../src/contracts/adapters/AdapterFactory.sol";
import {LiquidLaneAdapter} from "../../src/contracts/adapters/LiquidLaneAdapter.sol";
import {AdapterRegistry} from "../../src/contracts/AdapterRegistry.sol";
import {AccountRegistry} from "../../src/contracts/adapters/ll-adapter/AccountRegistry.sol";
import {AA_FalconX_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/AA_FalconX_Account.sol";
import {
    CarryTradeUSDTRYLeverage_Account
} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/CarryTradeUSDTRYLeverage_Account.sol";
import {UniversalDelegatorFactory} from "../../src/contracts/UniversalDelegatorFactory.sol";
import {JAAA_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/JAAA_Account.sol";
import {JTRSY_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/JTRSY_Account.sol";
import {PRIME_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/PRIME_Account.sol";
import {FigureSubAccount} from "../../src/contracts/adapters/ll-adapter/FigureAccount.sol";
import {FigureOracle} from "../../src/contracts/adapters/ll-adapter/oracles/FigureOracle.sol";
import {ParetoOracle} from "../../src/contracts/adapters/ll-adapter/oracles/ParetoOracle.sol";
import {
    StockMarketTRBasisTrade_Account
} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/StockMarketTRBasisTrade_Account.sol";
import {deJAAA_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/deJAAA_Account.sol";
import {deJTRSY_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/deJTRSY_Account.sol";
import {mFONE_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mFONE_Account.sol";
import {mGLOBAL_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mGLOBAL_Account.sol";
import {mHYPER_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mHYPER_Account.sol";
import {mM1USD_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mM1USD_Account.sol";
import {mROX_Account} from "../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mROX_Account.sol";
import {MigratablesFactory} from "../../src/contracts/common/MigratablesFactory.sol";
import {Registry} from "../../src/contracts/common/Registry.sol";
import {UniversalDelegator} from "../../src/contracts/delegator/UniversalDelegator.sol";
import {ILiquidLaneAdapter, MAX_TOKENS_TO_REDEEM} from "../../src/interfaces/adapters/ILiquidLaneAdapter.sol";
import {IAccount} from "../../src/interfaces/adapters/ll-adapter/IAccount.sol";
import {IAsyncRedeemAccount} from "../../src/interfaces/adapters/ll-adapter/IAsyncRedeemAccount.sol";
import {IERC7575Share} from "../../src/interfaces/adapters/ll-adapter/IERC7575Share.sol";
import {ICooldownAccount} from "../../src/interfaces/adapters/ll-adapter/ICooldownAccount.sol";
import {IFigureAccount} from "../../src/interfaces/adapters/ll-adapter/figure/IFigureAccount.sol";
import {IMidasAccount} from "../../src/interfaces/adapters/ll-adapter/midas/IMidasAccount.sol";
import {IMidasRedemptionVault} from "../../src/interfaces/adapters/ll-adapter/midas/IMidasRedemptionVault.sol";
import {IParetoAccount} from "../../src/interfaces/adapters/ll-adapter/pareto/IParetoAccount.sol";
import {IParetoCDO} from "../../src/interfaces/adapters/ll-adapter/pareto/IParetoCDO.sol";
import {
    IUniversalDelegator,
    MAX_SHARE,
    UNIVERSAL_DELEGATOR_VERSION
} from "../../src/interfaces/delegator/IUniversalDelegator.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract LiquidLaneAdapterAllTokensBenchmarkTest is MGlobalDataFeedHelper {
    using Math for uint256;

    address internal constant MAINNET_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant COW_SWAP_SETTLEMENT = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;
    address internal constant JAAA_TOKEN = 0x5a0F93D040De44e78F251b03c43be9CF317Dcf64;
    address internal constant JTRSY_TOKEN = 0x8c213ee79581Ff4984583C6a801e5263418C4b86;
    address internal constant DEJAAA_TOKEN = 0xAAA0008C8CF3A7Dca931adaF04336A5D808C82Cc;
    address internal constant DEJTRSY_TOKEN = 0xA6233014B9b7aaa74f38fa1977ffC7A89642dC72;
    address internal constant AA_FALCONX_TOKEN = 0xC26A6Fa2C37b38E549a4a1807543801Db684f99C;
    address internal constant PARETO_FALCONX_CDO = 0x433D5B175148dA32Ffe1e1A37a939E1b7e79be4d;

    address internal constant PRIME_TOKEN = 0x19ebb35279A16207Ec4ba82799CC64715065F7F6;
    address internal constant CENTRIFUGE_HOOK_WARD_1 = 0x7Ed48C31f2fdC40d37407cBaBf0870B2b688368f;
    address internal constant CENTRIFUGE_HOOK_WARD_2 = 0xEC3582fcDc34078a4B7a8c75a5a3AE46f48525aB;
    address internal constant MIDAS_ACCESS_CONTROL_ADMIN = 0xd4195CF4df289a4748C1A7B6dDBE770e27bA1227;
    address internal constant MIDAS_GREENLIST_ADMIN = 0xb5CcD8dC8082467849eE008d4242f7b3b569EF05;

    address internal curator = makeAddr("curator");
    address internal pauser = makeAddr("pauser");
    address internal unpauser = makeAddr("unpauser");

    BenchmarkVaultRegistry internal vaultFactory;
    AdapterFactory internal adapterFactory;
    AdapterRegistry internal adapterRegistry;
    AccountRegistry internal accountRegistry;
    UniversalDelegatorFactory internal delegatorFactory;
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

        assertEq(specs.length, 13);

        uint256 totalMaxAverageRequests;
        for (uint256 i; i < specs.length; ++i) {
            uint48 expectedCooldown = _cooldown(specs[i].symbol, specs[i].maxDelay);
            assertEq(specs[i].cooldown, expectedCooldown, specs[i].symbol);
            assertEq(
                specs[i].maxAverageRequests, _maxAverageRequests(specs[i].maxDelay, expectedCooldown), specs[i].symbol
            );
            totalMaxAverageRequests += specs[i].maxAverageRequests;
        }
        assertLe(specs.length, MAX_TOKENS_TO_REDEEM);
        assertEq(specs[3].cooldown, 18 hours, "PRIME");
        assertEq(totalMaxAverageRequests, 219);
    }

    function testBenchmarkOnboardsAllTokensToLiquidLaneAdapter() public {
        string memory rpcUrl = vm.envOr("ETH_RPC_URL", string(""));
        _skipWithoutRpc(rpcUrl, "ETH_RPC_URL is required for all-token LiquidLaneAdapter onboarding benchmark");

        vm.pauseGasMetering();
        _createFork(rpcUrl);
        _setUpAdapter();

        TokenBenchSpec[] memory specs = _tokenBenchSpecs();
        address[] memory tokens = _registerTokenFactories(specs);

        vm.resumeGasMetering();
        uint256 gasBefore = gasleft();
        _onboardTokens(tokens);
        uint256 onboardingGas = gasBefore - gasleft();

        vm.pauseGasMetering();
        assertEq(adapter.getTokensToRedeemLength(), 13);
        _logBench(specs, onboardingGas);
    }

    function testBenchmarkTotalAssetsAndSyncForEachAccount() public {
        string memory rpcUrl = vm.envOr("ETH_RPC_URL", string(""));
        _skipWithoutRpc(rpcUrl, "ETH_RPC_URL is required for account totalAssets/sync benchmark");

        vm.pauseGasMetering();
        _createFork(rpcUrl);
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
        _createFork(rpcUrl);
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
        delegatorFactory = new UniversalDelegatorFactory(curator);

        LiquidLaneAdapter implementation =
            new LiquidLaneAdapter(address(vaultFactory), address(adapterFactory), address(accountRegistry));
        UniversalDelegator delegatorImplementation =
            new UniversalDelegator(address(adapterRegistry), address(delegatorFactory));

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
            forceDeallocateRoleHolder: curator,
            setAdapterLimitsRoleHolder: curator,
            setAutoAllocateAdaptersRoleHolder: curator
        });
        delegator = UniversalDelegator(
            delegatorFactory.create(UNIVERSAL_DELEGATOR_VERSION, address(vault), abi.encode(delegatorParams))
        );
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
        if (_isFigure(index)) {
            return IERC4626(IERC4626(token).asset()).asset();
        }
        return MAINNET_USDC;
    }

    function _isMidas(uint256 index) internal pure returns (bool) {
        return index == 0 || index == 4 || (index >= 7 && index <= 11);
    }

    function _isCentrifuge(uint256 index) internal pure returns (bool) {
        return index == 1 || index == 2 || index == 5 || index == 6;
    }

    function _isFigure(uint256 index) internal pure returns (bool) {
        return index == 3;
    }

    function _mockVaultAsset(address asset) internal {
        vm.mockCall(address(vault), abi.encodeCall(IERC4626.asset, ()), abi.encode(asset));
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
                (bool success, bytes memory data) = account.staticcall(abi.encodeCall(IAccount.totalAssets, ()));
                totalAssetsGas = gasBefore - gasleft();
                totalAssetsSuccess = success;
                assets = success ? abi.decode(data, (uint256)) : 0;

                gasBefore = gasleft();
                (syncSuccess,) = account.call(abi.encodeCall(IAccount.sync, ()));
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

        emit log_named_uint("accounts benchmarked", 44);
        emit log_named_uint("total totalAssets gas", totalTotalAssetsGas);
        emit log_named_uint("total sync gas", totalSyncGas);
    }

    function _benchmarkAggregateGas() internal returns (AggregateGasBench memory bench) {
        vm.resumeGasMetering();
        uint256 gasBefore = gasleft();
        (bool adapterTotalAssetsSuccess,) =
            address(adapter).staticcall(abi.encodeCall(LiquidLaneAdapter.totalAssets, ()));
        uint256 adapterTotalAssetsGas = gasBefore - gasleft();

        gasBefore = gasleft();
        (bool delegatorTotalAssetsSuccess,) =
            address(delegator).staticcall(abi.encodeCall(UniversalDelegator.totalAssets, ()));
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
        uint256 startTimestamp = vm.getBlockTimestamp();
        uint48 cooldown = _requestCooldown(account);
        uint256 targetRequests = _seedTarget(index, spec);
        uint256 requestsBefore = _requestUnits(index, account);
        for (uint256 i; seeded < targetRequests && i < targetRequests; ++i) {
            if (i > 0 && cooldown > 0) {
                vm.warp(vm.getBlockTimestamp() + cooldown);
            }

            _fundRequest(index, token, account);

            vm.prank(curator);
            (bool success, bytes memory reason) = account.call(abi.encodeCall(IAccount.sync, ()));
            if (!success) {
                emit log_named_bytes("sync revert", reason);
                emit log_named_uint("token balance", IERC20(token).balanceOf(account));
                deal(token, account, 0);
                vm.warp(startTimestamp);
                return seeded;
            }

            uint256 requestsAfter = _requestUnits(index, account);
            if (requestsAfter <= requestsBefore) {
                vm.warp(startTimestamp);
                return seeded;
            }

            seeded += requestsAfter - requestsBefore;
            requestsBefore = requestsAfter;
        }
        vm.warp(startTimestamp);
    }

    function _requestCooldown(address account) internal view returns (uint48) {
        try ICooldownAccount(account).COOLDOWN() returns (uint48 cooldown) {
            return cooldown;
        } catch {
            return 0;
        }
    }

    function _seedTarget(uint256 index, TokenBenchSpec memory spec) internal pure returns (uint256) {
        if (index == 12) {
            return 1;
        }
        // Figure rejects a second PRIME redemption for ~36h after the first (longer than the account's
        // 18h cooldown), so only one standing request can be seeded.
        if (index == 3) {
            return 1;
        }
        return spec.maxAverageRequests;
    }

    function _fundRequest(uint256 index, address token, address account) internal {
        uint256 amount = _requestAmount(token);
        if (_isCentrifuge(index)) {
            _permissionCentrifugeMember(token, account);
            _dealCentrifugeShare(token, account, amount);
            return;
        }
        if (_isMidas(index)) {
            _configureMidasRequestPath(index, token, account);
        }
        if (index == 12) {
            _permissionParetoAccount(account);
            deal(token, account, amount);
            return;
        }
        if (_tryMintERC4626Shares(token, account, amount)) {
            return;
        }

        deal(token, account, amount);
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
        bytes memory callData = abi.encodeCall(ICentrifugeTransferHook.updateMember, (token, account, type(uint64).max));

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
        (bool success,) = dataFeed.staticcall(abi.encodeCall(IMidasDataFeed.getDataInBase18, ()));
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
            (bool approveSuccess,) = asset.call(abi.encodeCall(IERC20.approve, (token, assets)));
            if (!approveSuccess) {
                return false;
            }

            vm.prank(account);
            (bool mintSuccess,) = token.call(abi.encodeCall(IERC4626.mint, (shares, account)));
            return mintSuccess;
        } catch {
            return false;
        }
    }

    function _requestAmount(address token) internal view returns (uint256) {
        return 100 * 10 ** IERC20Metadata(token).decimals();
    }

    function _requestUnits(uint256 index, address account) internal view returns (uint256) {
        if (_isMidas(index)) {
            return _midasRequestIdsLength(account);
        }
        if (_isCentrifuge(index)) {
            return _asyncRequestIdsLength(account);
        }
        if (_isFigure(index)) {
            return _figureSubAccountsLength(account);
        }
        if (index == 12) {
            return _paretoQueueEpochsLength(account);
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

    function _paretoQueueEpochsLength(address account) internal view returns (uint256 length) {
        while (true) {
            try IParetoAccount(account).queueEpochs(length) returns (uint256) {
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

    function _figureSubAccountsLength(address account) internal view returns (uint256 length) {
        while (true) {
            try IFigureAccount(account).subAccounts(length) returns (address) {
                ++length;
            } catch {
                return length;
            }
        }
    }

    function _tokenBenchSpecs() internal pure returns (TokenBenchSpec[] memory specs) {
        specs = new TokenBenchSpec[](13);
        specs[0] = _spec("CarryTradeUSDTRYLeverage", 2 days);
        specs[1] = _spec("JAAA", 1 days);
        specs[2] = _spec("JTRSY", 1 days);
        specs[3] = _spec("PRIME", 1 days);
        specs[4] = _spec("StockMarketTRBasisTrade", 2 days);
        specs[5] = _spec("deJAAA", 1 days);
        specs[6] = _spec("deJTRSY", 1 days);
        specs[7] = _spec("mFONE", 35 days);
        specs[8] = _spec("mGLOBAL", 65 days);
        specs[9] = _spec("mHYPER", 3 days);
        specs[10] = _spec("mM1USD", 17 days);
        specs[11] = _spec("mROX", 3 days);
        // A request arriving just after NETTING can wait through the current and next full epoch.
        specs[12] = _spec("AA_FalconXUSDC", 66 days);
    }

    function _deployImplementation(uint256 index, address factory) internal returns (IAccount implementation) {
        if (index == 0) {
            return IAccount(address(new CarryTradeUSDTRYLeverage_Account(factory, COW_SWAP_SETTLEMENT)));
        }
        if (index == 1) {
            return IAccount(
                address(
                    new JAAA_Account(
                        _oracle(),
                        factory,
                        MAINNET_USDC,
                        IERC7575Share(JAAA_TOKEN).vault(MAINNET_USDC),
                        COW_SWAP_SETTLEMENT
                    )
                )
            );
        }
        if (index == 2) {
            return IAccount(
                address(
                    new JTRSY_Account(
                        _oracle(),
                        factory,
                        MAINNET_USDC,
                        IERC7575Share(JTRSY_TOKEN).vault(MAINNET_USDC),
                        COW_SWAP_SETTLEMENT
                    )
                )
            );
        }
        if (_isFigure(index)) {
            address token = PRIME_TOKEN;
            address subAccountImplementation = address(new FigureSubAccount(token));
            address oracle = address(new FigureOracle(1, type(uint256).max, token));
            return
                IAccount(
                    address(new PRIME_Account(oracle, factory, token, subAccountImplementation, COW_SWAP_SETTLEMENT))
                );
        }
        if (index == 4) {
            return IAccount(address(new StockMarketTRBasisTrade_Account(factory, COW_SWAP_SETTLEMENT)));
        }
        if (index == 5) {
            return IAccount(
                address(
                    new deJAAA_Account(
                        _oracle(),
                        factory,
                        MAINNET_USDC,
                        IERC7575Share(DEJAAA_TOKEN).vault(MAINNET_USDC),
                        COW_SWAP_SETTLEMENT
                    )
                )
            );
        }
        if (index == 6) {
            return IAccount(
                address(
                    new deJTRSY_Account(
                        _oracle(),
                        factory,
                        MAINNET_USDC,
                        IERC7575Share(DEJTRSY_TOKEN).vault(MAINNET_USDC),
                        COW_SWAP_SETTLEMENT
                    )
                )
            );
        }
        if (index == 7) {
            return IAccount(address(new mFONE_Account(factory, COW_SWAP_SETTLEMENT)));
        }
        if (index == 8) {
            return IAccount(address(new mGLOBAL_Account(factory, COW_SWAP_SETTLEMENT, MGLOBAL_DATA_FEED)));
        }
        if (index == 9) {
            return IAccount(address(new mHYPER_Account(factory, COW_SWAP_SETTLEMENT)));
        }
        if (index == 10) {
            return IAccount(address(new mM1USD_Account(factory, COW_SWAP_SETTLEMENT)));
        }
        if (index == 11) {
            return IAccount(address(new mROX_Account(factory, COW_SWAP_SETTLEMENT)));
        }
        if (index == 12) {
            return IAccount(
                address(
                    new AA_FalconX_Account(
                        address(new ParetoOracle(0.9e18, 1.5e18, AA_FALCONX_TOKEN, PARETO_FALCONX_CDO)),
                        factory,
                        COW_SWAP_SETTLEMENT
                    )
                )
            );
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
        if (keccak256(bytes(symbol)) == keccak256("mFONE")) {
            return 36 hours;
        }
        if (keccak256(bytes(symbol)) == keccak256("mGLOBAL")) {
            return 12 hours;
        }
        if (keccak256(bytes(symbol)) == keccak256("mHYPER")) {
            return 6 hours;
        }
        if (keccak256(bytes(symbol)) == keccak256("mM1USD")) {
            return 1 days;
        }
        if (keccak256(bytes(symbol)) == keccak256("mROX")) {
            return 6 hours;
        }
        if (keccak256(bytes(symbol)) == keccak256("CarryTradeUSDTRYLeverage")) {
            return 12 hours;
        }
        if (keccak256(bytes(symbol)) == keccak256("StockMarketTRBasisTrade")) {
            return 12 hours;
        }
        if (keccak256(bytes(symbol)) == keccak256("PRIME")) {
            return 18 hours;
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

    function _permissionParetoAccount(address account) internal {
        vm.mockCall(PARETO_FALCONX_CDO, abi.encodeCall(IParetoCDO.isEpochRunning, ()), abi.encode(true));
        vm.mockCall(PARETO_FALCONX_CDO, abi.encodeCall(IParetoCDO.isWalletAllowed, (account)), abi.encode(true));
    }

    function _logBench(TokenBenchSpec[] memory specs, uint256 onboardingGas) internal {
        uint256 totalMaxAverageRequests;
        emit log_named_uint("tokens onboarded", 44);
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

    function _createFork(string memory rpcUrl) internal {
        uint256 forkBlock = vm.envOr("MAINNET_FORK_BLOCK", uint256(0));
        if (forkBlock == 0) {
            vm.createSelectFork(rpcUrl);
        } else {
            vm.createSelectFork(rpcUrl, forkBlock);
        }
        _mockMGlobalDataFeed();
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

    /// @dev Settlement accounts (USCC/bEQTY), ACRED and other CutoffAccount hosts read
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

interface IOwnable {
    function owner() external view returns (address);
}

interface IDSServiceConsumer {
    function getDSService(uint256 serviceId) external view returns (address);
}

interface IDSRegistryService {
    function addWallet(address wallet, string calldata investorId) external returns (bool);

    function getCountry(string calldata investorId) external view returns (string memory);

    function isInvestor(string calldata investorId) external view returns (bool);

    function isWallet(address wallet) external view returns (bool);

    function registerInvestor(string calldata investorId, string calldata collisionHash) external returns (bool);

    function setCountry(string calldata investorId, string calldata country) external returns (bool);

    function setAttribute(
        string calldata investorId,
        uint8 attributeId,
        uint256 value,
        uint256 expiry,
        string calldata proofHash
    ) external returns (bool);
}

interface IDSecuritizeToken {
    function issueTokens(address account, uint256 amount) external returns (bool);
}

interface IDSComplianceConfigurationService {
    function getUSLockPeriod() external view returns (uint256);
}

interface IDSTrustService {
    function setRole(address account, uint8 role) external returns (bool);
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
