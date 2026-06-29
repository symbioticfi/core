// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";

import {DeployCoreBaseScript} from "../base/DeployCoreBase.s.sol";
import {DeployV2BaseScript} from "../base/DeployV2Base.s.sol";
import {TestnetVaultFactory} from "./TestnetVaultFactory.sol";
import {Logs} from "../../utils/Logs.sol";
import {SymbioticCoreConstants} from "../../../test/integration/SymbioticCoreConstants.sol";

import {AaveV3Adapter} from "../../../src/contracts/adapters/AaveV3Adapter.sol";
import {AdapterFactory} from "../../../src/contracts/adapters/AdapterFactory.sol";
import {AppAdapter} from "../../../src/contracts/adapters/AppAdapter.sol";
import {LiquidLaneAdapter} from "../../../src/contracts/adapters/LiquidLaneAdapter.sol";
import {MorphoVaultV2Adapter} from "../../../src/contracts/adapters/MorphoVaultV2Adapter.sol";
import {RestakingAppAdapter} from "../../../src/contracts/adapters/RestakingAppAdapter.sol";
import {AccountRegistry} from "../../../src/contracts/adapters/ll-adapter/AccountRegistry.sol";
import {MidasCompAccount, MidasNonCompAccount} from "../../../src/contracts/adapters/ll-adapter/MidasAccount.sol";
import {MidasOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/MidasOracle.sol";
import {MigratablesFactory} from "../../../src/contracts/common/MigratablesFactory.sol";
import {VaultFactory} from "../../../src/contracts/VaultFactory.sol";

import {IAdapterRegistry} from "../../../src/interfaces/IAdapterRegistry.sol";
import {IAaveV3Adapter} from "../../../src/interfaces/adapters/IAaveV3Adapter.sol";
import {IAppAdapter} from "../../../src/interfaces/adapters/IAppAdapter.sol";
import {ILiquidLaneAdapter} from "../../../src/interfaces/adapters/ILiquidLaneAdapter.sol";
import {IMorphoVaultV2Adapter} from "../../../src/interfaces/adapters/IMorphoVaultV2Adapter.sol";
import {IRestakingAppAdapter} from "../../../src/interfaces/adapters/IRestakingAppAdapter.sol";
import {ICoWSwapSettlement} from "../../../src/interfaces/adapters/common/ICoWSwapConverter.sol";
import {IMidasDataFeed} from "../../../src/interfaces/adapters/ll-adapter/midas/IMidasOracle.sol";
import {IMidasRedemptionVault} from "../../../src/interfaces/adapters/ll-adapter/midas/IMidasRedemptionVault.sol";
import {IUniversalDelegator, MAX_SHARE} from "../../../src/interfaces/delegator/IUniversalDelegator.sol";
import {IVaultV2, VAULT_V2_VERSION} from "../../../src/interfaces/vault/IVaultV2.sol";
import {
    MockAaveAToken,
    MockAavePool,
    MockAavePoolAddressesProvider,
    MockAavePoolDataProvider,
    MockMorphoAdapterRegistry,
    MockMorphoVaultFactory
} from "../../../test/mocks/HoodiScenarioProtocolMocks.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract DeployFullCoreLiquidLaneTestnetScript is Script {
    uint48 internal constant MFONE_COOLDOWN = 3 days;
    uint48 internal constant MGLOBAL_COOLDOWN = 6 days;
    uint256 internal constant DEFAULT_MINT_AMOUNT = 1_000_000 ether;
    uint256 internal constant DEFAULT_LIQUID_LANE_LIMIT = type(uint128).max;

    struct DeployParams {
        address owner;
        address marketMaker;
        address cowSwapSettlement;
        address cowSwapVaultRelayer;
        address usdc;
        address aUsd;
        address mFone;
        address mGlobal;
        address mFoneRedemptionVault;
        address mGlobalRedemptionVault;
        address merklDistributor;
        uint256 mintAmount;
        uint256 liquidLaneLimit;
        uint256 minDiscount;
    }

    struct TokenDeployments {
        address usdc;
        address aUsd;
        address mFone;
        address mGlobal;
    }

    struct RedemptionDeployments {
        address mFoneDataFeed;
        address mGlobalDataFeed;
        address mFoneRedemptionVault;
        address mGlobalRedemptionVault;
    }

    struct CowSwapDeployments {
        address settlement;
        address vaultRelayer;
    }

    struct AccountDeployments {
        address accountRegistry;
        address mFoneOracle;
        address mGlobalOracle;
        address mFoneAccountFactory;
        address mGlobalAccountFactory;
        address mFoneAccountImplementation;
        address mGlobalAccountImplementation;
    }

    struct LiquidLaneDeployments {
        address adapterFactory;
        address adapterImplementation;
        address usdcVault;
        address usdcDelegator;
        address usdcAdapter;
        address usdcMFoneAccount;
        address usdcMGlobalAccount;
        address aUsdVault;
        address aUsdDelegator;
        address aUsdAdapter;
        address aUsdMFoneAccount;
        address aUsdMGlobalAccount;
    }

    struct FullAdapterDeployments {
        address appAdapterFactory;
        address appAdapterImplementation;
        address merklDistributor;
        address burnerRouterFactory;
        address mockSwapRouter;
        address usdcBurner;
        address aUsdBurner;
        address usdcAppAdapter;
        address aUsdAppAdapter;
        address aaveAdapterFactory;
        address aaveAdapterImplementation;
        address mockAavePool;
        address mockAaveProvider;
        address mockAaveDataProvider;
        address mockAaveUsdcAToken;
        address mockAaveAusdAToken;
        address usdcAaveAdapter;
        address aUsdAaveAdapter;
        address morphoAdapterFactory;
        address morphoAdapterImplementation;
        address mockMorphoVaultFactory;
        address mockMorphoAdapterRegistry;
        address mockMorphoVaultUsdc;
        address mockMorphoVaultAusd;
        address usdcMorphoAdapter;
        address aUsdMorphoAdapter;
        address restakingAppAdapterFactory;
        address restakingAppAdapterImplementation;
        address usdcRestakingVault;
        address usdcRestakingDelegator;
        address usdcRestakingAppAdapter;
        address aUsdRestakingVault;
        address aUsdRestakingDelegator;
        address aUsdRestakingAppAdapter;
    }

    struct RestakingVaultConfig {
        address underlyingVault;
        address baseAsset;
        address burner;
        string name;
        string symbol;
        uint96 subnetworkId;
    }

    struct DeploymentData {
        SymbioticCoreConstants.Core core;
        DeployV2BaseScript.DeploymentData v2;
        TokenDeployments tokens;
        RedemptionDeployments redemptions;
        CowSwapDeployments cowSwap;
        AccountDeployments accounts;
        LiquidLaneDeployments liquidLane;
        FullAdapterDeployments fullAdapters;
        uint256 liquidLaneLimit;
        uint256 minDiscount;
    }

    function run() public returns (DeploymentData memory data) {
        address owner = vm.envOr("TESTNET_OWNER", _scriptOwner());
        data = runBase(
            DeployParams({
                owner: owner,
                marketMaker: vm.envOr("TESTNET_MARKET_MAKER", owner),
                cowSwapSettlement: vm.envOr("TESTNET_COW_SWAP_SETTLEMENT", address(0)),
                cowSwapVaultRelayer: vm.envOr("TESTNET_COW_SWAP_VAULT_RELAYER", address(0)),
                usdc: vm.envOr("TESTNET_USDC", address(0)),
                aUsd: vm.envOr("TESTNET_AUSD", address(0)),
                mFone: vm.envOr("TESTNET_MFONE", address(0)),
                mGlobal: vm.envOr("TESTNET_MGLOBAL", address(0)),
                mFoneRedemptionVault: vm.envOr("TESTNET_MFONE_REDEMPTION_VAULT", address(0)),
                mGlobalRedemptionVault: vm.envOr("TESTNET_MGLOBAL_REDEMPTION_VAULT", address(0)),
                merklDistributor: vm.envOr("TESTNET_MERKL_DISTRIBUTOR", address(0)),
                mintAmount: vm.envOr("TESTNET_MINT_AMOUNT", DEFAULT_MINT_AMOUNT),
                liquidLaneLimit: vm.envOr("TESTNET_LIQUID_LANE_LIMIT", DEFAULT_LIQUID_LANE_LIMIT),
                minDiscount: vm.envOr("TESTNET_MIN_DISCOUNT", uint256(0))
            })
        );
    }

    function runBase(DeployParams memory params) public virtual returns (DeploymentData memory data) {
        _validateParams(params);

        data.core = _deployCore(params.owner);
        data.v2 = _deployV2(data.core, params.owner);

        _startBroadcast();
        data.tokens = _deployOrUseTokens(params);
        data.redemptions = _deployOrUseRedemptions(params, data.tokens);
        data.cowSwap = _deployOrUseCowSwap(params);
        data.accounts = _deployAccounts(params, data.tokens, data.redemptions, data.cowSwap.settlement);
        data.liquidLane = _deployLiquidLane(data.core, data.v2, params, data.tokens, data.accounts);
        data.fullAdapters = _deployFullAdapters(data.core, data.v2, params, data.tokens, data.cowSwap, data.liquidLane);
        data.liquidLaneLimit = params.liquidLaneLimit;
        data.minDiscount = params.minDiscount;
        _mintMocks(params, data.tokens);
        _stopBroadcast();

        _logDeployment(data);
    }

    function _validateParams(DeployParams memory params) internal view {
        require(params.owner != address(0), "invalid owner");
        require(params.marketMaker != address(0), "invalid market maker");
        require(params.minDiscount <= 1_000_000, "invalid min discount");
    }

    function _deployCore(address owner) internal virtual returns (SymbioticCoreConstants.Core memory core) {
        DeployCoreBaseScript.CoreDeploymentData memory coreData =
            new DeployFullCoreLiquidLaneTestnetCoreScript(_broadcast(), owner).run(owner);
        core = _coreFrom(coreData);
    }

    function _deployV2(SymbioticCoreConstants.Core memory core, address owner)
        internal
        virtual
        returns (DeployV2BaseScript.DeploymentData memory data)
    {
        data = new DeployFullCoreLiquidLaneTestnetV2Script(core, _broadcast(), owner).runBase(owner, owner);
    }

    function _deployOrUseTokens(DeployParams memory params) internal returns (TokenDeployments memory tokens) {
        tokens.usdc = params.usdc == address(0) ? _deployMockToken("Testnet USDC", "USDC", 6) : params.usdc;
        tokens.aUsd = params.aUsd == address(0) ? _deployMockToken("Testnet aUSD", "aUSD", 18) : params.aUsd;
        tokens.mFone = params.mFone == address(0) ? _deployMockToken("Testnet mF-ONE", "mF-ONE", 18) : params.mFone;
        tokens.mGlobal =
            params.mGlobal == address(0) ? _deployMockToken("Testnet mGLOBAL", "mGLOBAL", 18) : params.mGlobal;
    }

    function _deployOrUseRedemptions(DeployParams memory params, TokenDeployments memory tokens)
        internal
        returns (RedemptionDeployments memory redemptions)
    {
        redemptions.mFoneDataFeed = address(new TestnetMidasDataFeedMock(1e18));
        redemptions.mGlobalDataFeed = address(new TestnetMidasDataFeedMock(1e18));
        redemptions.mFoneRedemptionVault = params.mFoneRedemptionVault == address(0)
            ? address(new TestnetMidasRedemptionVaultMock(tokens.mFone, tokens.usdc, redemptions.mFoneDataFeed))
            : params.mFoneRedemptionVault;
        redemptions.mGlobalRedemptionVault = params.mGlobalRedemptionVault == address(0)
            ? address(new TestnetMidasRedemptionVaultMock(tokens.mGlobal, tokens.usdc, redemptions.mGlobalDataFeed))
            : params.mGlobalRedemptionVault;

        redemptions.mFoneDataFeed = address(IMidasRedemptionVault(redemptions.mFoneRedemptionVault).mTokenDataFeed());
        redemptions.mGlobalDataFeed =
            address(IMidasRedemptionVault(redemptions.mGlobalRedemptionVault).mTokenDataFeed());
    }

    function _deployOrUseCowSwap(DeployParams memory params) internal returns (CowSwapDeployments memory cowSwap) {
        if (params.cowSwapSettlement != address(0)) {
            cowSwap.settlement = params.cowSwapSettlement;
            cowSwap.vaultRelayer = ICoWSwapSettlement(cowSwap.settlement).vaultRelayer();
            return cowSwap;
        }

        cowSwap.vaultRelayer = params.cowSwapVaultRelayer == address(0)
            ? address(new TestnetCowSwapVaultRelayerMock())
            : params.cowSwapVaultRelayer;
        cowSwap.settlement = address(new TestnetCowSwapSettlementMock(cowSwap.vaultRelayer));
    }

    function _deployAccounts(
        DeployParams memory params,
        TokenDeployments memory tokens,
        RedemptionDeployments memory redemptions,
        address cowSwapSettlement
    ) internal returns (AccountDeployments memory accounts) {
        accounts.accountRegistry = address(new AccountRegistry(params.owner));
        (uint256 mFoneMinPrice, uint256 mFoneMaxPrice) =
            _oraclePriceBounds(IMidasDataFeed(redemptions.mFoneDataFeed).getDataInBase18());
        (uint256 mGlobalMinPrice, uint256 mGlobalMaxPrice) =
            _oraclePriceBounds(IMidasDataFeed(redemptions.mGlobalDataFeed).getDataInBase18());
        accounts.mFoneOracle = address(new MidasOracle(mFoneMinPrice, mFoneMaxPrice, redemptions.mFoneDataFeed));
        accounts.mGlobalOracle = address(new MidasOracle(mGlobalMinPrice, mGlobalMaxPrice, redemptions.mGlobalDataFeed));

        accounts.mFoneAccountFactory = address(new MigratablesFactory(params.owner));
        accounts.mGlobalAccountFactory = address(new MigratablesFactory(params.owner));
        accounts.mFoneAccountImplementation = address(
            new MidasNonCompAccount(
                accounts.mFoneOracle,
                accounts.mFoneAccountFactory,
                MFONE_COOLDOWN,
                tokens.mFone,
                tokens.usdc,
                redemptions.mFoneRedemptionVault,
                cowSwapSettlement
            )
        );
        accounts.mGlobalAccountImplementation = address(
            new MidasCompAccount(
                accounts.mGlobalOracle,
                accounts.mGlobalAccountFactory,
                MGLOBAL_COOLDOWN,
                tokens.mGlobal,
                tokens.usdc,
                redemptions.mGlobalRedemptionVault,
                cowSwapSettlement
            )
        );

        MigratablesFactory(accounts.mFoneAccountFactory).whitelist(accounts.mFoneAccountImplementation);
        MigratablesFactory(accounts.mGlobalAccountFactory).whitelist(accounts.mGlobalAccountImplementation);
        AccountRegistry(accounts.accountRegistry)
            .setAccountFactory(tokens.usdc, tokens.mFone, accounts.mFoneAccountFactory);
        AccountRegistry(accounts.accountRegistry)
            .setAccountFactory(tokens.usdc, tokens.mGlobal, accounts.mGlobalAccountFactory);
        AccountRegistry(accounts.accountRegistry)
            .setAccountFactory(tokens.aUsd, tokens.mFone, accounts.mFoneAccountFactory);
        AccountRegistry(accounts.accountRegistry)
            .setAccountFactory(tokens.aUsd, tokens.mGlobal, accounts.mGlobalAccountFactory);
    }

    function _deployLiquidLane(
        SymbioticCoreConstants.Core memory core,
        DeployV2BaseScript.DeploymentData memory v2,
        DeployParams memory params,
        TokenDeployments memory tokens,
        AccountDeployments memory accounts
    ) internal returns (LiquidLaneDeployments memory liquidLane) {
        liquidLane.adapterFactory = address(new AdapterFactory(params.owner));
        liquidLane.adapterImplementation = address(
            new LiquidLaneAdapter(address(core.vaultFactory), liquidLane.adapterFactory, accounts.accountRegistry)
        );
        AdapterFactory(liquidLane.adapterFactory).whitelist(liquidLane.adapterImplementation);

        (liquidLane.usdcVault, liquidLane.usdcDelegator, liquidLane.usdcAdapter) =
            _deployVaultAndAdapter(core, v2, params, tokens, tokens.usdc, "Testnet USDC Vault", "tUSDC-V", liquidLane);
        (liquidLane.aUsdVault, liquidLane.aUsdDelegator, liquidLane.aUsdAdapter) =
            _deployVaultAndAdapter(core, v2, params, tokens, tokens.aUsd, "Testnet aUSD Vault", "taUSD-V", liquidLane);

        liquidLane.usdcMFoneAccount = ILiquidLaneAdapter(liquidLane.usdcAdapter).accounts(tokens.mFone);
        liquidLane.usdcMGlobalAccount = ILiquidLaneAdapter(liquidLane.usdcAdapter).accounts(tokens.mGlobal);
        liquidLane.aUsdMFoneAccount = ILiquidLaneAdapter(liquidLane.aUsdAdapter).accounts(tokens.mFone);
        liquidLane.aUsdMGlobalAccount = ILiquidLaneAdapter(liquidLane.aUsdAdapter).accounts(tokens.mGlobal);
    }

    function _deployVaultAndAdapter(
        SymbioticCoreConstants.Core memory core,
        DeployV2BaseScript.DeploymentData memory v2,
        DeployParams memory params,
        TokenDeployments memory tokens,
        address asset,
        string memory name,
        string memory symbol,
        LiquidLaneDeployments memory liquidLane
    ) internal returns (address vault, address delegator, address adapter) {
        vault = core.vaultFactory.create(VAULT_V2_VERSION, params.owner, _vaultParams(params, asset, name, symbol));
        delegator = IVaultV2(vault).delegator();

        adapter = AdapterFactory(liquidLane.adapterFactory)
            .create(
                1,
                params.owner,
                abi.encode(
                    vault, abi.encode(ILiquidLaneAdapter.InitParams({pauser: params.owner, unpauser: params.owner}))
                )
            );
        IAdapterRegistry(address(v2.adapterRegistry)).setWhitelistedStatus(vault, adapter, true);
        IUniversalDelegator(delegator).addAdapter(adapter);
        IUniversalDelegator(delegator).setLimits(adapter, params.liquidLaneLimit, MAX_SHARE);

        ILiquidLaneAdapter(adapter).addTokenToRedeem(tokens.mFone);
        ILiquidLaneAdapter(adapter).addTokenToRedeem(tokens.mGlobal);
        ILiquidLaneAdapter(adapter).setLimit(tokens.mFone, params.liquidLaneLimit);
        ILiquidLaneAdapter(adapter).setLimit(tokens.mGlobal, params.liquidLaneLimit);
        ILiquidLaneAdapter(adapter).setMinDiscount(tokens.mFone, params.minDiscount);
        ILiquidLaneAdapter(adapter).setMinDiscount(tokens.mGlobal, params.minDiscount);
        ILiquidLaneAdapter(adapter).setMarketMaker(params.marketMaker, true);
    }

    function _deployFullAdapters(
        SymbioticCoreConstants.Core memory core,
        DeployV2BaseScript.DeploymentData memory v2,
        DeployParams memory params,
        TokenDeployments memory tokens,
        CowSwapDeployments memory cowSwap,
        LiquidLaneDeployments memory liquidLane
    ) internal returns (FullAdapterDeployments memory fullAdapters) {
        fullAdapters.merklDistributor = params.merklDistributor == address(0)
            ? address(new TestnetMerklDistributorMock())
            : params.merklDistributor;
        _deployAppStack(core, v2, params, tokens, cowSwap.settlement, liquidLane, fullAdapters);
        _deployAaveStack(core, v2, params, tokens, cowSwap.settlement, liquidLane, fullAdapters);
        _deployMorphoStack(core, v2, params, tokens, cowSwap.settlement, liquidLane, fullAdapters);
        _deployRestakingAppStack(core, v2, params, tokens, cowSwap.settlement, liquidLane, fullAdapters);
    }

    function _deployAppStack(
        SymbioticCoreConstants.Core memory core,
        DeployV2BaseScript.DeploymentData memory v2,
        DeployParams memory params,
        TokenDeployments memory tokens,
        address cowSwapSettlement,
        LiquidLaneDeployments memory liquidLane,
        FullAdapterDeployments memory fullAdapters
    ) internal {
        fullAdapters.burnerRouterFactory = address(new TestnetBurnerRouterFactoryMock());
        fullAdapters.mockSwapRouter = address(new TestnetSwapRouterMock());
        fullAdapters.usdcBurner =
            _createBurner(fullAdapters.burnerRouterFactory, params.owner, tokens.usdc, params.owner);
        fullAdapters.aUsdBurner =
            _createBurner(fullAdapters.burnerRouterFactory, params.owner, tokens.aUsd, params.owner);

        fullAdapters.appAdapterFactory = address(new AdapterFactory(params.owner));
        fullAdapters.appAdapterImplementation = address(
            new AppAdapter(
                address(core.vaultFactory),
                fullAdapters.appAdapterFactory,
                cowSwapSettlement,
                address(core.networkMiddlewareService)
            )
        );
        AdapterFactory(fullAdapters.appAdapterFactory).whitelist(fullAdapters.appAdapterImplementation);

        fullAdapters.usdcAppAdapter =
            _createAppAdapter(fullAdapters.appAdapterFactory, params, liquidLane.usdcVault, fullAdapters.usdcBurner, 1);
        _attachAdapter(v2, params, liquidLane.usdcVault, liquidLane.usdcDelegator, fullAdapters.usdcAppAdapter);
        fullAdapters.aUsdAppAdapter =
            _createAppAdapter(fullAdapters.appAdapterFactory, params, liquidLane.aUsdVault, fullAdapters.aUsdBurner, 2);
        _attachAdapter(v2, params, liquidLane.aUsdVault, liquidLane.aUsdDelegator, fullAdapters.aUsdAppAdapter);
    }

    function _deployAaveStack(
        SymbioticCoreConstants.Core memory core,
        DeployV2BaseScript.DeploymentData memory v2,
        DeployParams memory params,
        TokenDeployments memory tokens,
        address cowSwapSettlement,
        LiquidLaneDeployments memory liquidLane,
        FullAdapterDeployments memory fullAdapters
    ) internal {
        fullAdapters.mockAaveUsdcAToken = address(new MockAaveAToken(tokens.usdc, params.owner));
        fullAdapters.mockAaveAusdAToken = address(new MockAaveAToken(tokens.aUsd, params.owner));
        fullAdapters.mockAaveProvider = address(new MockAavePoolAddressesProvider(params.owner));
        fullAdapters.mockAaveDataProvider = address(new MockAavePoolDataProvider(params.owner));
        fullAdapters.mockAavePool = address(
            new MockAavePool(tokens.usdc, fullAdapters.mockAaveUsdcAToken, fullAdapters.mockAaveProvider, params.owner)
        );
        MockAavePool(fullAdapters.mockAavePool).setReserveToken(tokens.aUsd, fullAdapters.mockAaveAusdAToken);
        MockAaveAToken(fullAdapters.mockAaveUsdcAToken).setPool(fullAdapters.mockAavePool);
        MockAaveAToken(fullAdapters.mockAaveAusdAToken).setPool(fullAdapters.mockAavePool);
        MockAavePoolAddressesProvider(fullAdapters.mockAaveProvider).setPool(fullAdapters.mockAavePool);
        MockAavePoolAddressesProvider(fullAdapters.mockAaveProvider)
            .setPoolDataProvider(fullAdapters.mockAaveDataProvider);
        MockAavePoolDataProvider(fullAdapters.mockAaveDataProvider)
            .setReserveToken(tokens.usdc, fullAdapters.mockAaveUsdcAToken);
        MockAavePoolDataProvider(fullAdapters.mockAaveDataProvider)
            .setReserveToken(tokens.aUsd, fullAdapters.mockAaveAusdAToken);

        fullAdapters.aaveAdapterFactory = address(new AdapterFactory(params.owner));
        fullAdapters.aaveAdapterImplementation = address(
            new AaveV3Adapter(
                fullAdapters.mockAavePool,
                address(core.vaultFactory),
                fullAdapters.aaveAdapterFactory,
                fullAdapters.merklDistributor,
                cowSwapSettlement
            )
        );
        AdapterFactory(fullAdapters.aaveAdapterFactory).whitelist(fullAdapters.aaveAdapterImplementation);

        fullAdapters.usdcAaveAdapter =
            _createAaveAdapter(fullAdapters.aaveAdapterFactory, params.owner, liquidLane.usdcVault);
        _attachAdapter(v2, params, liquidLane.usdcVault, liquidLane.usdcDelegator, fullAdapters.usdcAaveAdapter);
        fullAdapters.aUsdAaveAdapter =
            _createAaveAdapter(fullAdapters.aaveAdapterFactory, params.owner, liquidLane.aUsdVault);
        _attachAdapter(v2, params, liquidLane.aUsdVault, liquidLane.aUsdDelegator, fullAdapters.aUsdAaveAdapter);
    }

    function _deployMorphoStack(
        SymbioticCoreConstants.Core memory core,
        DeployV2BaseScript.DeploymentData memory v2,
        DeployParams memory params,
        TokenDeployments memory tokens,
        address cowSwapSettlement,
        LiquidLaneDeployments memory liquidLane,
        FullAdapterDeployments memory fullAdapters
    ) internal {
        fullAdapters.mockMorphoAdapterRegistry = address(new MockMorphoAdapterRegistry(params.owner));
        fullAdapters.mockMorphoVaultFactory =
            address(new MockMorphoVaultFactory(fullAdapters.mockMorphoAdapterRegistry, params.owner));
        (, fullAdapters.mockMorphoVaultUsdc) =
            MockMorphoVaultFactory(fullAdapters.mockMorphoVaultFactory).createVault(tokens.usdc);
        (, fullAdapters.mockMorphoVaultAusd) =
            MockMorphoVaultFactory(fullAdapters.mockMorphoVaultFactory).createVault(tokens.aUsd);
        MockMorphoAdapterRegistry(fullAdapters.mockMorphoAdapterRegistry)
            .setInRegistry(fullAdapters.mockMorphoVaultUsdc, true);
        MockMorphoAdapterRegistry(fullAdapters.mockMorphoAdapterRegistry)
            .setInRegistry(fullAdapters.mockMorphoVaultAusd, true);

        fullAdapters.morphoAdapterFactory = address(new AdapterFactory(params.owner));
        fullAdapters.morphoAdapterImplementation = address(
            new MorphoVaultV2Adapter(
                address(core.vaultFactory),
                fullAdapters.morphoAdapterFactory,
                fullAdapters.merklDistributor,
                cowSwapSettlement,
                fullAdapters.mockMorphoVaultFactory,
                fullAdapters.mockMorphoAdapterRegistry
            )
        );
        AdapterFactory(fullAdapters.morphoAdapterFactory).whitelist(fullAdapters.morphoAdapterImplementation);

        fullAdapters.usdcMorphoAdapter = _createMorphoAdapter(
            fullAdapters.morphoAdapterFactory, params.owner, liquidLane.usdcVault, fullAdapters.mockMorphoVaultUsdc
        );
        _attachAdapter(v2, params, liquidLane.usdcVault, liquidLane.usdcDelegator, fullAdapters.usdcMorphoAdapter);
        fullAdapters.aUsdMorphoAdapter = _createMorphoAdapter(
            fullAdapters.morphoAdapterFactory, params.owner, liquidLane.aUsdVault, fullAdapters.mockMorphoVaultAusd
        );
        _attachAdapter(v2, params, liquidLane.aUsdVault, liquidLane.aUsdDelegator, fullAdapters.aUsdMorphoAdapter);
    }

    function _deployRestakingAppStack(
        SymbioticCoreConstants.Core memory core,
        DeployV2BaseScript.DeploymentData memory v2,
        DeployParams memory params,
        TokenDeployments memory tokens,
        address cowSwapSettlement,
        LiquidLaneDeployments memory liquidLane,
        FullAdapterDeployments memory fullAdapters
    ) internal {
        fullAdapters.restakingAppAdapterFactory = address(new AdapterFactory(params.owner));
        fullAdapters.restakingAppAdapterImplementation = address(
            new RestakingAppAdapter(
                address(core.vaultFactory),
                fullAdapters.restakingAppAdapterFactory,
                cowSwapSettlement,
                address(core.networkMiddlewareService)
            )
        );
        AdapterFactory(fullAdapters.restakingAppAdapterFactory)
            .whitelist(fullAdapters.restakingAppAdapterImplementation);

        (fullAdapters.usdcRestakingVault, fullAdapters.usdcRestakingDelegator, fullAdapters.usdcRestakingAppAdapter) =
            _deployRestakingVaultAndAdapter(
                core,
                v2,
                params,
                RestakingVaultConfig({
                    underlyingVault: liquidLane.usdcVault,
                    baseAsset: tokens.usdc,
                    burner: fullAdapters.usdcBurner,
                    name: "Testnet USDC Restaking Vault",
                    symbol: "tUSDC-RV",
                    subnetworkId: 101
                }),
                fullAdapters
            );
        (fullAdapters.aUsdRestakingVault, fullAdapters.aUsdRestakingDelegator, fullAdapters.aUsdRestakingAppAdapter) =
            _deployRestakingVaultAndAdapter(
                core,
                v2,
                params,
                RestakingVaultConfig({
                    underlyingVault: liquidLane.aUsdVault,
                    baseAsset: tokens.aUsd,
                    burner: fullAdapters.aUsdBurner,
                    name: "Testnet aUSD Restaking Vault",
                    symbol: "taUSD-RV",
                    subnetworkId: 102
                }),
                fullAdapters
            );
    }

    function _deployRestakingVaultAndAdapter(
        SymbioticCoreConstants.Core memory core,
        DeployV2BaseScript.DeploymentData memory v2,
        DeployParams memory params,
        RestakingVaultConfig memory config,
        FullAdapterDeployments memory fullAdapters
    ) internal returns (address vault, address delegator, address adapter) {
        vault = core.vaultFactory
            .create(
                VAULT_V2_VERSION, params.owner, _vaultParams(params, config.underlyingVault, config.name, config.symbol)
            );
        delegator = IVaultV2(vault).delegator();

        bytes memory adapterData = _restakingAppAdapterData(
            vault,
            config.baseAsset,
            config.burner,
            params.marketMaker,
            _testnetSubnetwork(params.owner, config.subnetworkId)
        );
        adapter = AdapterFactory(fullAdapters.restakingAppAdapterFactory).create(1, params.owner, adapterData);
        _attachAdapter(v2, params, vault, delegator, adapter);
    }

    function _createBurner(address burnerRouterFactory, address owner, address collateral, address globalReceiver)
        internal
        returns (address)
    {
        TestnetBurnerRouterFactoryMock.NetworkReceiver[] memory networkReceivers =
            new TestnetBurnerRouterFactoryMock.NetworkReceiver[](0);
        TestnetBurnerRouterFactoryMock.OperatorNetworkReceiver[] memory operatorNetworkReceivers =
            new TestnetBurnerRouterFactoryMock.OperatorNetworkReceiver[](0);
        return TestnetBurnerRouterFactoryMock(burnerRouterFactory)
            .create(
                TestnetBurnerRouterFactoryMock.InitParams({
                owner: owner,
                collateral: collateral,
                delay: 0,
                globalReceiver: globalReceiver,
                networkReceivers: networkReceivers,
                operatorNetworkReceivers: operatorNetworkReceivers
            })
            );
    }

    function _createAppAdapter(
        address factory,
        DeployParams memory params,
        address vault,
        address burner,
        uint96 subnetworkId
    ) internal returns (address) {
        address[] memory converters = new address[](0);
        return AdapterFactory(factory)
            .create(
                1,
                params.owner,
                abi.encode(
                    vault,
                    abi.encode(
                        IAppAdapter.InitParams({
                        burner: burner,
                        duration: 1 days,
                        operator: params.marketMaker,
                        converters: converters,
                        subnetwork: _testnetSubnetwork(params.owner, subnetworkId)
                    })
                    )
                )
            );
    }

    function _createAaveAdapter(address factory, address owner, address vault) internal returns (address) {
        address[] memory converters = new address[](0);
        return AdapterFactory(factory)
            .create(1, owner, abi.encode(vault, abi.encode(IAaveV3Adapter.InitParams({converters: converters}))));
    }

    function _createMorphoAdapter(address factory, address owner, address vault, address morphoVault)
        internal
        returns (address)
    {
        address[] memory converters = new address[](0);
        return AdapterFactory(factory)
            .create(
                1,
                owner,
                abi.encode(
                    vault,
                    abi.encode(IMorphoVaultV2Adapter.InitParams({morphoVault: morphoVault, converters: converters}))
                )
            );
    }

    function _restakingAppAdapterData(
        address vault,
        address asset,
        address burner,
        address operator,
        bytes32 subnetwork
    ) internal pure returns (bytes memory) {
        address[] memory converters = new address[](0);
        IAppAdapter.InitParams memory initParams = IAppAdapter.InitParams({
            burner: burner, duration: 1 days, operator: operator, converters: converters, subnetwork: subnetwork
        });
        return
            abi.encode(
                vault, abi.encode(IRestakingAppAdapter.RestakingInitParams({asset: asset, initParams: initParams}))
            );
    }

    function _attachAdapter(
        DeployV2BaseScript.DeploymentData memory v2,
        DeployParams memory params,
        address vault,
        address delegator,
        address adapter
    ) internal {
        IAdapterRegistry(address(v2.adapterRegistry)).setWhitelistedStatus(vault, adapter, true);
        IUniversalDelegator(delegator).addAdapter(adapter);
        IUniversalDelegator(delegator).setLimits(adapter, params.liquidLaneLimit, MAX_SHARE);
    }

    function _testnetSubnetwork(address network, uint96 identifier) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(network)) << 96 | identifier);
    }

    function _oraclePriceBounds(uint256 price) internal pure returns (uint256 minPrice, uint256 maxPrice) {
        minPrice = price / 2;
        maxPrice = price * 2;
    }

    function _vaultParams(DeployParams memory params, address asset, string memory name, string memory symbol)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(
            IVaultV2.InitParams({
                name: name,
                symbol: symbol,
                asset: asset,
                depositWhitelist: false,
                depositorToWhitelist: address(0),
                depositLimit: type(uint256).max,
                isDepositLimit: true,
                defaultAdminRoleHolder: params.owner,
                managementFeeRoleHolder: params.owner,
                performanceFeeRoleHolder: params.owner,
                depositLimitSetRoleHolder: params.owner,
                depositorWhitelistRoleHolder: params.owner,
                isDepositLimitSetRoleHolder: params.owner,
                depositWhitelistSetRoleHolder: params.owner,
                delegatorParams: abi.encode(_delegatorParams(params.owner))
            })
        );
    }

    function _delegatorParams(address owner) internal pure returns (IUniversalDelegator.InitParams memory params) {
        params = IUniversalDelegator.InitParams({
            allocateRoleHolder: owner,
            deallocateRoleHolder: owner,
            forceDeallocateRoleHolder: owner,
            addAdapterRoleHolder: owner,
            swapAdaptersRoleHolder: owner,
            defaultAdminRoleHolder: owner,
            removeAdapterRoleHolder: owner,
            setAdapterLimitsRoleHolder: owner,
            setAutoAllocateAdaptersRoleHolder: owner
        });
    }

    function _deployMockToken(string memory name, string memory symbol, uint8 decimals_) internal returns (address) {
        return address(new TestnetERC20Mock(name, symbol, decimals_));
    }

    function _mintMocks(DeployParams memory params, TokenDeployments memory tokens) internal {
        _tryMint(tokens.usdc, params.owner, params.mintAmount);
        _tryMint(tokens.usdc, params.marketMaker, params.mintAmount);
        _tryMint(tokens.aUsd, params.owner, params.mintAmount);
        _tryMint(tokens.aUsd, params.marketMaker, params.mintAmount);
        _tryMint(tokens.mFone, params.owner, params.mintAmount);
        _tryMint(tokens.mFone, params.marketMaker, params.mintAmount);
        _tryMint(tokens.mGlobal, params.owner, params.mintAmount);
        _tryMint(tokens.mGlobal, params.marketMaker, params.mintAmount);
    }

    function _tryMint(address token, address to, uint256 amount) internal {
        if (amount == 0 || to == address(0)) {
            return;
        }
        (bool success,) = token.call(abi.encodeCall(TestnetERC20Mock.mint, (to, amount)));
        success;
    }

    function _coreFrom(DeployCoreBaseScript.CoreDeploymentData memory data)
        internal
        pure
        returns (SymbioticCoreConstants.Core memory core)
    {
        core = SymbioticCoreConstants.Core({
            vaultFactory: data.vaultFactory,
            delegatorFactory: data.delegatorFactory,
            slasherFactory: data.slasherFactory,
            networkRegistry: data.networkRegistry,
            networkMetadataService: data.networkMetadataService,
            networkMiddlewareService: data.networkMiddlewareService,
            operatorRegistry: data.operatorRegistry,
            operatorMetadataService: data.operatorMetadataService,
            operatorVaultOptInService: data.operatorVaultOptInService,
            operatorNetworkOptInService: data.operatorNetworkOptInService,
            vaultConfigurator: data.vaultConfigurator
        });
    }

    function _logDeployment(DeploymentData memory data) internal {
        Logs.log("DeployFullCoreLiquidLaneTestnet deployment");
        Logs.log(string.concat("VaultFactory: ", vm.toString(address(data.core.vaultFactory))));
        Logs.log(string.concat("DelegatorFactory: ", vm.toString(address(data.core.delegatorFactory))));
        Logs.log(string.concat("SlasherFactory: ", vm.toString(address(data.core.slasherFactory))));
        Logs.log(string.concat("AdapterRegistry: ", vm.toString(address(data.v2.adapterRegistry))));
        Logs.log(string.concat("ProtocolFeeRegistry: ", vm.toString(address(data.v2.protocolFeeRegistry))));
        Logs.log(string.concat("WithdrawalQueueFactory: ", vm.toString(address(data.v2.withdrawalQueueFactory))));
        Logs.log(string.concat("WithdrawalQueue: ", vm.toString(address(data.v2.withdrawalQueue))));
        Logs.log(string.concat("VaultV2 implementation: ", vm.toString(address(data.v2.vaultV2))));
        Logs.log(string.concat("UniversalDelegator implementation: ", vm.toString(address(data.v2.universalDelegator))));
        Logs.log(string.concat("USDC: ", vm.toString(data.tokens.usdc)));
        Logs.log(string.concat("aUSD: ", vm.toString(data.tokens.aUsd)));
        Logs.log(string.concat("mFONE: ", vm.toString(data.tokens.mFone)));
        Logs.log(string.concat("mGLOBAL: ", vm.toString(data.tokens.mGlobal)));
        Logs.log(string.concat("mFONE data feed: ", vm.toString(data.redemptions.mFoneDataFeed)));
        Logs.log(string.concat("mGLOBAL data feed: ", vm.toString(data.redemptions.mGlobalDataFeed)));
        Logs.log(string.concat("mFONE redemption vault: ", vm.toString(data.redemptions.mFoneRedemptionVault)));
        Logs.log(string.concat("mGLOBAL redemption vault: ", vm.toString(data.redemptions.mGlobalRedemptionVault)));
        Logs.log(string.concat("CowSwap settlement: ", vm.toString(data.cowSwap.settlement)));
        Logs.log(string.concat("CowSwap vault relayer: ", vm.toString(data.cowSwap.vaultRelayer)));
        Logs.log(string.concat("AccountRegistry: ", vm.toString(data.accounts.accountRegistry)));
        Logs.log(string.concat("mFONE oracle: ", vm.toString(data.accounts.mFoneOracle)));
        Logs.log(string.concat("mGLOBAL oracle: ", vm.toString(data.accounts.mGlobalOracle)));
        Logs.log(string.concat("mFONE account factory: ", vm.toString(data.accounts.mFoneAccountFactory)));
        Logs.log(string.concat("mGLOBAL account factory: ", vm.toString(data.accounts.mGlobalAccountFactory)));
        Logs.log(string.concat("mFONE account implementation: ", vm.toString(data.accounts.mFoneAccountImplementation)));
        Logs.log(
            string.concat("mGLOBAL account implementation: ", vm.toString(data.accounts.mGlobalAccountImplementation))
        );
        Logs.log(string.concat("LiquidLane adapter factory: ", vm.toString(data.liquidLane.adapterFactory)));
        Logs.log(
            string.concat("LiquidLane adapter implementation: ", vm.toString(data.liquidLane.adapterImplementation))
        );
        Logs.log(string.concat("USDC vault: ", vm.toString(data.liquidLane.usdcVault)));
        Logs.log(string.concat("USDC delegator: ", vm.toString(data.liquidLane.usdcDelegator)));
        Logs.log(string.concat("USDC LiquidLane adapter: ", vm.toString(data.liquidLane.usdcAdapter)));
        Logs.log(string.concat("USDC mFONE account: ", vm.toString(data.liquidLane.usdcMFoneAccount)));
        Logs.log(string.concat("USDC mGLOBAL account: ", vm.toString(data.liquidLane.usdcMGlobalAccount)));
        Logs.log(string.concat("aUSD vault: ", vm.toString(data.liquidLane.aUsdVault)));
        Logs.log(string.concat("aUSD delegator: ", vm.toString(data.liquidLane.aUsdDelegator)));
        Logs.log(string.concat("aUSD LiquidLane adapter: ", vm.toString(data.liquidLane.aUsdAdapter)));
        Logs.log(string.concat("aUSD mFONE account: ", vm.toString(data.liquidLane.aUsdMFoneAccount)));
        Logs.log(string.concat("aUSD mGLOBAL account: ", vm.toString(data.liquidLane.aUsdMGlobalAccount)));
        Logs.log(string.concat("App adapter factory: ", vm.toString(data.fullAdapters.appAdapterFactory)));
        Logs.log(string.concat("App adapter implementation: ", vm.toString(data.fullAdapters.appAdapterImplementation)));
        Logs.log(string.concat("Merkl distributor: ", vm.toString(data.fullAdapters.merklDistributor)));
        Logs.log(string.concat("Burner router factory: ", vm.toString(data.fullAdapters.burnerRouterFactory)));
        Logs.log(string.concat("Mock swap router: ", vm.toString(data.fullAdapters.mockSwapRouter)));
        Logs.log(string.concat("USDC burner router: ", vm.toString(data.fullAdapters.usdcBurner)));
        Logs.log(string.concat("aUSD burner router: ", vm.toString(data.fullAdapters.aUsdBurner)));
        Logs.log(string.concat("USDC App adapter: ", vm.toString(data.fullAdapters.usdcAppAdapter)));
        Logs.log(string.concat("aUSD App adapter: ", vm.toString(data.fullAdapters.aUsdAppAdapter)));
        Logs.log(string.concat("AaveV3 adapter factory: ", vm.toString(data.fullAdapters.aaveAdapterFactory)));
        Logs.log(
            string.concat("AaveV3 adapter implementation: ", vm.toString(data.fullAdapters.aaveAdapterImplementation))
        );
        Logs.log(string.concat("Mock Aave pool: ", vm.toString(data.fullAdapters.mockAavePool)));
        Logs.log(string.concat("Mock Aave provider: ", vm.toString(data.fullAdapters.mockAaveProvider)));
        Logs.log(string.concat("Mock Aave data provider: ", vm.toString(data.fullAdapters.mockAaveDataProvider)));
        Logs.log(string.concat("Mock Aave USDC aToken: ", vm.toString(data.fullAdapters.mockAaveUsdcAToken)));
        Logs.log(string.concat("Mock Aave aUSD aToken: ", vm.toString(data.fullAdapters.mockAaveAusdAToken)));
        Logs.log(string.concat("USDC AaveV3 adapter: ", vm.toString(data.fullAdapters.usdcAaveAdapter)));
        Logs.log(string.concat("aUSD AaveV3 adapter: ", vm.toString(data.fullAdapters.aUsdAaveAdapter)));
        Logs.log(string.concat("MorphoVaultV2 adapter factory: ", vm.toString(data.fullAdapters.morphoAdapterFactory)));
        Logs.log(
            string.concat(
                "MorphoVaultV2 adapter implementation: ", vm.toString(data.fullAdapters.morphoAdapterImplementation)
            )
        );
        Logs.log(string.concat("Mock Morpho vault factory: ", vm.toString(data.fullAdapters.mockMorphoVaultFactory)));
        Logs.log(
            string.concat("Mock Morpho adapter registry: ", vm.toString(data.fullAdapters.mockMorphoAdapterRegistry))
        );
        Logs.log(string.concat("Mock Morpho USDC vault: ", vm.toString(data.fullAdapters.mockMorphoVaultUsdc)));
        Logs.log(string.concat("Mock Morpho aUSD vault: ", vm.toString(data.fullAdapters.mockMorphoVaultAusd)));
        Logs.log(string.concat("USDC MorphoVaultV2 adapter: ", vm.toString(data.fullAdapters.usdcMorphoAdapter)));
        Logs.log(string.concat("aUSD MorphoVaultV2 adapter: ", vm.toString(data.fullAdapters.aUsdMorphoAdapter)));
        Logs.log(
            string.concat("RestakingApp adapter factory: ", vm.toString(data.fullAdapters.restakingAppAdapterFactory))
        );
        Logs.log(
            string.concat(
                "RestakingApp adapter implementation: ",
                vm.toString(data.fullAdapters.restakingAppAdapterImplementation)
            )
        );
        Logs.log(string.concat("USDC restaking vault: ", vm.toString(data.fullAdapters.usdcRestakingVault)));
        Logs.log(string.concat("USDC restaking delegator: ", vm.toString(data.fullAdapters.usdcRestakingDelegator)));
        Logs.log(string.concat("USDC RestakingApp adapter: ", vm.toString(data.fullAdapters.usdcRestakingAppAdapter)));
        Logs.log(string.concat("aUSD restaking vault: ", vm.toString(data.fullAdapters.aUsdRestakingVault)));
        Logs.log(string.concat("aUSD restaking delegator: ", vm.toString(data.fullAdapters.aUsdRestakingDelegator)));
        Logs.log(string.concat("aUSD RestakingApp adapter: ", vm.toString(data.fullAdapters.aUsdRestakingAppAdapter)));
    }

    function _broadcast() internal view virtual returns (bool) {
        return true;
    }

    function _startBroadcast() internal virtual {
        if (_broadcast()) {
            vm.startBroadcast();
        } else {
            address owner = _scriptOwner();
            vm.startPrank(owner, owner);
        }
    }

    function _stopBroadcast() internal virtual {
        if (_broadcast()) {
            vm.stopBroadcast();
        } else {
            vm.stopPrank();
        }
    }

    function _scriptOwner() internal view virtual returns (address owner) {
        (,, address origin) = vm.readCallers();
        owner = origin == address(0) ? msg.sender : origin;
    }
}

contract DeployFullCoreLiquidLaneTestnetCoreScript is DeployCoreBaseScript {
    bool internal immutable _useBroadcast;
    address internal immutable _owner;

    constructor(bool useBroadcast, address owner_) {
        _useBroadcast = useBroadcast;
        _owner = owner_;
    }

    function _startBroadcast() internal override {
        if (_useBroadcast) {
            vm.startBroadcast();
        } else {
            vm.startPrank(_owner, _owner);
        }
    }

    function _stopBroadcast() internal override {
        if (_useBroadcast) {
            vm.stopBroadcast();
        } else {
            vm.stopPrank();
        }
    }

    function _deployVaultFactory(address owner) internal override returns (VaultFactory) {
        return VaultFactory(address(new TestnetVaultFactory(owner)));
    }
}

contract DeployFullCoreLiquidLaneTestnetV2Script is DeployV2BaseScript {
    SymbioticCoreConstants.Core internal _localCore;
    bool internal immutable _useBroadcast;
    address internal immutable _owner;

    constructor(SymbioticCoreConstants.Core memory core_, bool useBroadcast, address owner_) {
        _localCore = core_;
        _useBroadcast = useBroadcast;
        _owner = owner_;
    }

    function _startBroadcast() internal override {
        if (_useBroadcast) {
            vm.startBroadcast();
        } else {
            vm.startPrank(_owner, _owner);
        }
    }

    function _stopBroadcast() internal override {
        if (_useBroadcast) {
            vm.stopBroadcast();
        } else {
            vm.stopPrank();
        }
    }

    function _scriptOwner() internal view override returns (address owner) {
        if (!_useBroadcast) {
            return _owner;
        }
        return super._scriptOwner();
    }

    function _core() internal view override returns (SymbioticCoreConstants.Core memory) {
        return _localCore;
    }

    function runBase(address adapterRegistryOwner, address protocolFeeRegistryOwner)
        public
        override
        returns (DeploymentData memory data)
    {
        data = super.runBase(adapterRegistryOwner, protocolFeeRegistryOwner);

        _startBroadcast();
        if (VaultFactory(address(data.core.vaultFactory)).lastVersion() < VAULT_V2_VERSION) {
            VaultFactory(address(data.core.vaultFactory)).whitelist(address(data.vaultV2));
        }
        _stopBroadcast();

        assert(VaultFactory(address(data.core.vaultFactory)).implementation(VAULT_V2_VERSION) == address(data.vaultV2));
    }
}

contract TestnetCowSwapVaultRelayerMock {}

contract TestnetCowSwapSettlementMock {
    address public immutable vaultRelayer;
    bytes32 public immutable domainSeparator = keccak256("TESTNET_COW_SWAP_DOMAIN");
    bytes public lastOrderUid;
    bool public lastSigned;

    constructor(address vaultRelayer_) {
        vaultRelayer = vaultRelayer_;
    }

    function setPreSignature(bytes calldata orderUid, bool signed) external {
        lastOrderUid = orderUid;
        lastSigned = signed;
    }
}

contract TestnetMerklDistributorMock {
    uint256 public claimCalls;
    uint256 public lastUsersLength;
    uint256 public lastTokensLength;
    uint256 public lastAmountsLength;
    uint256 public lastProofsLength;

    function claim(
        address[] calldata users,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs
    ) external {
        ++claimCalls;
        lastUsersLength = users.length;
        lastTokensLength = tokens.length;
        lastAmountsLength = amounts.length;
        lastProofsLength = proofs.length;
    }
}

contract TestnetBurnerRouterFactoryMock {
    struct NetworkReceiver {
        address network;
        address receiver;
    }

    struct OperatorNetworkReceiver {
        address network;
        address operator;
        address receiver;
    }

    struct InitParams {
        address owner;
        address collateral;
        uint48 delay;
        address globalReceiver;
        NetworkReceiver[] networkReceivers;
        OperatorNetworkReceiver[] operatorNetworkReceivers;
    }

    event AddEntity(address indexed entity);

    address[] internal _entities;

    function totalEntities() external view returns (uint256) {
        return _entities.length;
    }

    function entity(uint256 index) external view returns (address) {
        return _entities[index];
    }

    function create(InitParams calldata params) external returns (address router) {
        router =
            address(new TestnetBurnerRouterMock(params.owner, params.collateral, params.delay, params.globalReceiver));
        _entities.push(router);

        emit AddEntity(router);
    }
}

contract TestnetBurnerRouterMock {
    address public immutable owner;
    address public immutable collateral;
    uint48 public immutable delay;
    address public immutable globalReceiver;

    uint256 public slashCalls;
    bytes32 public lastSubnetwork;
    address public lastOperator;
    uint256 public lastAmount;
    uint48 public lastCaptureTimestamp;

    constructor(address owner_, address collateral_, uint48 delay_, address globalReceiver_) {
        owner = owner_;
        collateral = collateral_;
        delay = delay_;
        globalReceiver = globalReceiver_;
    }

    function onSlash(bytes32 subnetwork, address operator, uint256 amount, uint48 captureTimestamp) external {
        ++slashCalls;
        lastSubnetwork = subnetwork;
        lastOperator = operator;
        lastAmount = amount;
        lastCaptureTimestamp = captureTimestamp;
    }
}

contract TestnetSwapRouterMock {
    mapping(address tokenIn => mapping(address tokenOut => uint256 rate)) public rates;

    function setRate(address tokenIn, address tokenOut, uint256 rate) external {
        rates[tokenIn][tokenOut] = rate;
    }
}

contract TestnetERC20Mock is ERC20 {
    uint8 internal immutable _customDecimals;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _customDecimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _customDecimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract TestnetMidasDataFeedMock {
    uint256 public immutable answer;

    constructor(uint256 answer_) {
        answer = answer_;
    }

    function getDataInBase18() external view returns (uint256) {
        return answer;
    }
}

contract TestnetMidasRedemptionVaultMock {
    uint8 internal constant REQUEST_STATUS_PROCESSED = 1;

    struct Request {
        address sender;
        address tokenOut;
        uint8 status;
        uint256 amountMToken;
        uint256 mTokenRate;
        uint256 tokenOutRate;
    }

    address public immutable tokenToRedeem;
    address public immutable redemptionToken;
    address public immutable mTokenDataFeed;
    uint256 public currentRequestId;

    mapping(address token => address dataFeed) public dataFeedOf;
    mapping(uint256 requestId => Request request) internal _requests;

    constructor(address tokenToRedeem_, address redemptionToken_, address mTokenDataFeed_) {
        tokenToRedeem = tokenToRedeem_;
        redemptionToken = redemptionToken_;
        mTokenDataFeed = mTokenDataFeed_;
        dataFeedOf[redemptionToken_] = mTokenDataFeed_;
    }

    function tokensConfig(address token)
        external
        view
        returns (address dataFeed, uint256 fee, uint256 allowance_, bool stable)
    {
        dataFeed = dataFeedOf[token];
        allowance_ = type(uint256).max;
        stable = token == redemptionToken;
    }

    function redeemRequest(address tokenOut, uint256 amountMTokenIn) external returns (uint256 requestId) {
        require(IERC20(tokenToRedeem).transferFrom(msg.sender, address(this), amountMTokenIn), "transfer-from");

        uint256 mTokenRate = TestnetMidasDataFeedMock(mTokenDataFeed).getDataInBase18();
        uint256 tokenOutRate = _tokenRate(tokenOut);
        requestId = currentRequestId++;
        _requests[requestId] = Request({
            sender: msg.sender,
            tokenOut: tokenOut,
            status: REQUEST_STATUS_PROCESSED,
            amountMToken: amountMTokenIn,
            mTokenRate: mTokenRate,
            tokenOutRate: tokenOutRate
        });

        uint256 redemptionAmount = amountMTokenIn * mTokenRate * 10 ** IERC20Metadata(redemptionToken).decimals()
            / (1e18 * 10 ** IERC20Metadata(tokenToRedeem).decimals());
        TestnetERC20Mock(redemptionToken).mint(msg.sender, redemptionAmount);
    }

    function redeemRequests(uint256 requestId)
        external
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
        Request memory request = _requests[requestId];
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
        address dataFeed = dataFeedOf[token];
        if (dataFeed == address(0)) {
            return 1e18;
        }
        return TestnetMidasDataFeedMock(dataFeed).getDataInBase18();
    }
}
