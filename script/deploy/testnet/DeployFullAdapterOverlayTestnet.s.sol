// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";

import {AdapterRegistry} from "../../../src/contracts/AdapterRegistry.sol";
import {AaveV3Adapter} from "../../../src/contracts/adapters/AaveV3Adapter.sol";
import {AdapterFactory} from "../../../src/contracts/adapters/AdapterFactory.sol";
import {AppAdapter} from "../../../src/contracts/adapters/AppAdapter.sol";
import {MorphoVaultV2Adapter} from "../../../src/contracts/adapters/MorphoVaultV2Adapter.sol";

import {IAdapterRegistry} from "../../../src/interfaces/IAdapterRegistry.sol";
import {IAaveV3Adapter} from "../../../src/interfaces/adapters/IAaveV3Adapter.sol";
import {IAppAdapter} from "../../../src/interfaces/adapters/IAppAdapter.sol";
import {IMorphoVaultV2Adapter} from "../../../src/interfaces/adapters/IMorphoVaultV2Adapter.sol";
import {IUniversalDelegator, MAX_SHARE} from "../../../src/interfaces/delegator/IUniversalDelegator.sol";

import {
    MockAaveAToken,
    MockAavePool,
    MockAavePoolAddressesProvider,
    MockAavePoolDataProvider,
    MockMorphoVaultFactory,
    MockMorphoVaultHarness
} from "../../../test/mocks/HoodiScenarioProtocolMocks.sol";
import {
    TestnetBurnerRouterFactoryMock,
    TestnetCowSwapSettlementMock,
    TestnetCowSwapVaultRelayerMock,
    TestnetSwapRouterMock
} from "./DeployFullCoreLiquidLaneTestnet.s.sol";

contract DeployFullAdapterOverlayTestnetScript is Script {
    uint256 internal constant DEFAULT_ADAPTER_LIMIT = type(uint128).max;

    struct DeployParams {
        address owner;
        address marketMaker;
        address vaultFactory;
        address adapterRegistry;
        address networkMiddlewareService;
        address cowSwapSettlement;
        address cowSwapVaultRelayer;
        address usdc;
        address aUsd;
        address usdcVault;
        address usdcDelegator;
        address aUsdVault;
        address aUsdDelegator;
        uint256 adapterLimit;
    }

    struct OverlayDeployments {
        address cowSwapSettlement;
        address cowSwapVaultRelayer;
        address appAdapterFactory;
        address appAdapterImplementation;
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
    }

    function run() public returns (OverlayDeployments memory overlay) {
        overlay = runBase(_paramsFromEnv());
    }

    function runBase(DeployParams memory params) public virtual returns (OverlayDeployments memory overlay) {
        _validateParams(params);

        _startBroadcast();
        _deployCowSwap(params, overlay);
        _deployAppStack(params, overlay);
        _deployAaveStack(params, overlay);
        _deployMorphoStack(params, overlay);
        _stopBroadcast();

        _logOverlay(overlay);
    }

    function _paramsFromEnv() internal view returns (DeployParams memory params) {
        string memory manifestPath = vm.envOr("TESTNET_DEPLOYMENT_JSON", string(""));
        string memory json = bytes(manifestPath).length == 0 ? "" : vm.readFile(manifestPath);

        params.owner = _addressFromJsonOrEnv(json, ".participants.protocolSigner", "TESTNET_OWNER", _scriptOwner());
        params.marketMaker =
            _addressFromJsonOrEnv(json, ".participants.marketMaker", "TESTNET_MARKET_MAKER", params.owner);
        params.vaultFactory =
            _addressFromJsonOrEnv(json, ".contracts.vaultFactory", "TESTNET_VAULT_FACTORY", address(0));
        params.adapterRegistry =
            _addressFromJsonOrEnv(json, ".contracts.adapterRegistry", "TESTNET_ADAPTER_REGISTRY", address(0));
        params.networkMiddlewareService = _addressFromJsonOrEnv(
            json, ".contracts.networkMiddlewareService", "TESTNET_NETWORK_MIDDLEWARE_SERVICE", address(0)
        );
        params.cowSwapSettlement =
            _addressFromJsonOrEnv(json, ".contracts.cowSwapSettlement", "TESTNET_COW_SWAP_SETTLEMENT", address(0));
        params.cowSwapVaultRelayer =
            _addressFromJsonOrEnv(json, ".contracts.cowSwapVaultRelayer", "TESTNET_COW_SWAP_VAULT_RELAYER", address(0));
        params.usdc = _addressFromJsonOrEnv(json, ".tokens.output[0].address", "TESTNET_USDC", address(0));
        params.aUsd = _addressFromJsonOrEnv(json, ".tokens.output[1].address", "TESTNET_AUSD", address(0));
        params.usdcVault = _addressFromJsonOrEnv(json, ".contracts.usdcVault", "TESTNET_USDC_VAULT", address(0));
        params.usdcDelegator =
            _addressFromJsonOrEnv(json, ".contracts.usdcDelegator", "TESTNET_USDC_DELEGATOR", address(0));
        params.aUsdVault = _addressFromJsonOrEnv(json, ".contracts.ausdVault", "TESTNET_AUSD_VAULT", address(0));
        params.aUsdDelegator =
            _addressFromJsonOrEnv(json, ".contracts.ausdDelegator", "TESTNET_AUSD_DELEGATOR", address(0));
        params.adapterLimit = vm.envOr("TESTNET_ADAPTER_LIMIT", DEFAULT_ADAPTER_LIMIT);
    }

    function _validateParams(DeployParams memory params) internal pure {
        require(params.owner != address(0), "invalid owner");
        require(params.marketMaker != address(0), "invalid market maker");
        require(params.vaultFactory != address(0), "invalid vault factory");
        require(params.adapterRegistry != address(0), "invalid adapter registry");
        require(params.usdc != address(0), "invalid usdc");
        require(params.aUsd != address(0), "invalid ausd");
        require(params.usdcVault != address(0), "invalid usdc vault");
        require(params.usdcDelegator != address(0), "invalid usdc delegator");
        require(params.aUsdVault != address(0), "invalid ausd vault");
        require(params.aUsdDelegator != address(0), "invalid ausd delegator");
    }

    function _deployCowSwap(DeployParams memory params, OverlayDeployments memory overlay) internal {
        if (params.cowSwapSettlement != address(0)) {
            overlay.cowSwapSettlement = params.cowSwapSettlement;
            overlay.cowSwapVaultRelayer = TestnetCowSwapSettlementMock(params.cowSwapSettlement).vaultRelayer();
            return;
        }

        overlay.cowSwapVaultRelayer = params.cowSwapVaultRelayer == address(0)
            ? address(new TestnetCowSwapVaultRelayerMock())
            : params.cowSwapVaultRelayer;
        overlay.cowSwapSettlement = address(new TestnetCowSwapSettlementMock(overlay.cowSwapVaultRelayer));
    }

    function _deployAppStack(DeployParams memory params, OverlayDeployments memory overlay) internal {
        overlay.burnerRouterFactory = address(new TestnetBurnerRouterFactoryMock());
        overlay.mockSwapRouter = address(new TestnetSwapRouterMock());
        overlay.usdcBurner = _createBurner(overlay.burnerRouterFactory, params.owner, params.usdc, params.owner);
        overlay.aUsdBurner = _createBurner(overlay.burnerRouterFactory, params.owner, params.aUsd, params.owner);

        overlay.appAdapterFactory = address(new AdapterFactory(params.owner));
        overlay.appAdapterImplementation = address(
            new AppAdapter(
                params.vaultFactory,
                overlay.appAdapterFactory,
                overlay.cowSwapSettlement,
                params.networkMiddlewareService
            )
        );
        AdapterFactory(overlay.appAdapterFactory).whitelist(overlay.appAdapterImplementation);

        overlay.usdcAppAdapter =
            _createAppAdapter(overlay.appAdapterFactory, params, params.usdcVault, overlay.usdcBurner, 1);
        _attachAdapter(params, params.usdcVault, params.usdcDelegator, overlay.usdcAppAdapter);
        overlay.aUsdAppAdapter =
            _createAppAdapter(overlay.appAdapterFactory, params, params.aUsdVault, overlay.aUsdBurner, 2);
        _attachAdapter(params, params.aUsdVault, params.aUsdDelegator, overlay.aUsdAppAdapter);
    }

    function _deployAaveStack(DeployParams memory params, OverlayDeployments memory overlay) internal {
        overlay.mockAaveUsdcAToken = address(new MockAaveAToken(params.usdc));
        overlay.mockAaveAusdAToken = address(new MockAaveAToken(params.aUsd));
        overlay.mockAaveProvider = address(new MockAavePoolAddressesProvider());
        overlay.mockAaveDataProvider = address(new MockAavePoolDataProvider());
        overlay.mockAavePool =
            address(new MockAavePool(params.usdc, overlay.mockAaveUsdcAToken, overlay.mockAaveProvider));
        MockAavePool(overlay.mockAavePool).setReserveToken(params.aUsd, overlay.mockAaveAusdAToken);
        MockAaveAToken(overlay.mockAaveUsdcAToken).setPool(overlay.mockAavePool);
        MockAaveAToken(overlay.mockAaveAusdAToken).setPool(overlay.mockAavePool);
        MockAavePoolAddressesProvider(overlay.mockAaveProvider).setPool(overlay.mockAavePool);
        MockAavePoolAddressesProvider(overlay.mockAaveProvider).setPoolDataProvider(overlay.mockAaveDataProvider);
        MockAavePoolDataProvider(overlay.mockAaveDataProvider).setReserveToken(params.usdc, overlay.mockAaveUsdcAToken);
        MockAavePoolDataProvider(overlay.mockAaveDataProvider).setReserveToken(params.aUsd, overlay.mockAaveAusdAToken);

        overlay.aaveAdapterFactory = address(new AdapterFactory(params.owner));
        overlay.aaveAdapterImplementation = address(
            new AaveV3Adapter(
                overlay.mockAavePool,
                params.vaultFactory,
                overlay.aaveAdapterFactory,
                params.owner,
                overlay.cowSwapSettlement
            )
        );
        AdapterFactory(overlay.aaveAdapterFactory).whitelist(overlay.aaveAdapterImplementation);

        overlay.usdcAaveAdapter = _createAaveAdapter(overlay.aaveAdapterFactory, params.owner, params.usdcVault);
        _attachAdapter(params, params.usdcVault, params.usdcDelegator, overlay.usdcAaveAdapter);
        overlay.aUsdAaveAdapter = _createAaveAdapter(overlay.aaveAdapterFactory, params.owner, params.aUsdVault);
        _attachAdapter(params, params.aUsdVault, params.aUsdDelegator, overlay.aUsdAaveAdapter);
    }

    function _deployMorphoStack(DeployParams memory params, OverlayDeployments memory overlay) internal {
        overlay.mockMorphoAdapterRegistry = address(new AdapterRegistry(params.owner));
        overlay.mockMorphoVaultFactory = address(new MockMorphoVaultFactory());
        overlay.mockMorphoVaultUsdc =
            address(new MockMorphoVaultHarness(params.usdc, overlay.mockMorphoAdapterRegistry));
        overlay.mockMorphoVaultAusd =
            address(new MockMorphoVaultHarness(params.aUsd, overlay.mockMorphoAdapterRegistry));
        MockMorphoVaultFactory(overlay.mockMorphoVaultFactory).setVault(overlay.mockMorphoVaultUsdc, true);
        MockMorphoVaultFactory(overlay.mockMorphoVaultFactory).setVault(overlay.mockMorphoVaultAusd, true);

        overlay.morphoAdapterFactory = address(new AdapterFactory(params.owner));
        overlay.morphoAdapterImplementation = address(
            new MorphoVaultV2Adapter(
                params.vaultFactory,
                overlay.morphoAdapterFactory,
                params.owner,
                overlay.cowSwapSettlement,
                overlay.mockMorphoVaultFactory,
                overlay.mockMorphoAdapterRegistry
            )
        );
        AdapterFactory(overlay.morphoAdapterFactory).whitelist(overlay.morphoAdapterImplementation);

        overlay.usdcMorphoAdapter = _createMorphoAdapter(
            overlay.morphoAdapterFactory, params.owner, params.usdcVault, overlay.mockMorphoVaultUsdc
        );
        _attachAdapter(params, params.usdcVault, params.usdcDelegator, overlay.usdcMorphoAdapter);
        overlay.aUsdMorphoAdapter = _createMorphoAdapter(
            overlay.morphoAdapterFactory, params.owner, params.aUsdVault, overlay.mockMorphoVaultAusd
        );
        _attachAdapter(params, params.aUsdVault, params.aUsdDelegator, overlay.aUsdMorphoAdapter);
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

    function _attachAdapter(DeployParams memory params, address vault, address delegator, address adapter) internal {
        IAdapterRegistry(params.adapterRegistry).setWhitelistedStatus(vault, adapter, true);
        IUniversalDelegator(delegator).addAdapter(adapter);
        IUniversalDelegator(delegator).setLimits(adapter, params.adapterLimit, MAX_SHARE);
    }

    function _addressFromJsonOrEnv(string memory json, string memory key, string memory envKey, address defaultValue)
        internal
        view
        returns (address)
    {
        if (bytes(json).length != 0 && vm.keyExistsJson(json, key)) {
            return vm.parseJsonAddress(json, key);
        }
        return vm.envOr(envKey, defaultValue);
    }

    function _testnetSubnetwork(address network, uint96 identifier) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(network)) << 96 | identifier);
    }

    function _logOverlay(OverlayDeployments memory overlay) internal view {
        _log("CowSwap settlement", overlay.cowSwapSettlement);
        _log("CowSwap vault relayer", overlay.cowSwapVaultRelayer);
        _log("App adapter factory", overlay.appAdapterFactory);
        _log("App adapter implementation", overlay.appAdapterImplementation);
        _log("Burner router factory", overlay.burnerRouterFactory);
        _log("Mock swap router", overlay.mockSwapRouter);
        _log("USDC burner router", overlay.usdcBurner);
        _log("aUSD burner router", overlay.aUsdBurner);
        _log("USDC App adapter", overlay.usdcAppAdapter);
        _log("aUSD App adapter", overlay.aUsdAppAdapter);
        _log("AaveV3 adapter factory", overlay.aaveAdapterFactory);
        _log("AaveV3 adapter implementation", overlay.aaveAdapterImplementation);
        _log("Mock Aave pool", overlay.mockAavePool);
        _log("Mock Aave provider", overlay.mockAaveProvider);
        _log("Mock Aave data provider", overlay.mockAaveDataProvider);
        _log("Mock Aave USDC aToken", overlay.mockAaveUsdcAToken);
        _log("Mock Aave aUSD aToken", overlay.mockAaveAusdAToken);
        _log("USDC AaveV3 adapter", overlay.usdcAaveAdapter);
        _log("aUSD AaveV3 adapter", overlay.aUsdAaveAdapter);
        _log("MorphoVaultV2 adapter factory", overlay.morphoAdapterFactory);
        _log("MorphoVaultV2 adapter implementation", overlay.morphoAdapterImplementation);
        _log("Mock Morpho vault factory", overlay.mockMorphoVaultFactory);
        _log("Mock Morpho adapter registry", overlay.mockMorphoAdapterRegistry);
        _log("Mock Morpho USDC vault", overlay.mockMorphoVaultUsdc);
        _log("Mock Morpho aUSD vault", overlay.mockMorphoVaultAusd);
        _log("USDC MorphoVaultV2 adapter", overlay.usdcMorphoAdapter);
        _log("aUSD MorphoVaultV2 adapter", overlay.aUsdMorphoAdapter);
    }

    function _log(string memory label, address value) internal view {
        string memory line = string.concat(label, ": ", vm.toString(value));
        bytes memory payload = abi.encodeWithSignature("log(string)", line);
        (bool success,) = address(0x000000000000000000636F6e736F6c652e6c6f67).staticcall(payload);
        success;
    }

    function _broadcast() internal view virtual returns (bool) {
        return true;
    }

    function _startBroadcast() internal virtual {
        if (_broadcast()) {
            vm.startBroadcast();
        } else {
            vm.startPrank(_scriptOwner(), _scriptOwner());
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
