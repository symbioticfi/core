// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";

import {AdapterRegistry} from "../../../src/contracts/AdapterRegistry.sol";
import {Logs} from "../../utils/Logs.sol";

import {Token} from "../../../test/mocks/Token.sol";
import {
    MockAaveAToken,
    MockAavePool,
    MockAavePoolAddressesProvider,
    MockAavePoolDataProvider,
    MockMorphoVaultFactory,
    MockMorphoVaultHarness
} from "../../../test/mocks/HoodiScenarioProtocolMocks.sol";

contract HoodiAdapterDependencyDeployBaseScript is Script {
    enum DependencyMode {
        Live,
        Mock
    }

    struct DependencySet {
        DependencyMode aaveMode;
        DependencyMode morphoMode;
        address curatorRegistry;
        address rewards;
        address feeRegistry;
        address collateral;
        address aavePool;
        address aaveProvider;
        address aaveDataProvider;
        address aToken;
        address morphoVaultFactory;
        address morphoAdapterRegistry;
        address morphoVault;
        address burnerRouterImplementation;
        address burnerRouterFactory;
    }

    function runBase(bool preferLive) public virtual returns (DependencySet memory deps) {
        address liveCollateral = vm.envOr("HOODI_COLLATERAL", address(0));

        deps.collateral = liveCollateral;
        if (deps.collateral == address(0)) {
            _startBroadcast();
            deps.collateral = address(new Token("Hoodi Collateral"));
            _stopBroadcast();
        }

        address liveAavePool = vm.envOr("HOODI_AAVE_POOL", address(0));
        address liveAaveProvider = vm.envOr("HOODI_AAVE_PROVIDER", address(0));
        address liveAaveDataProvider = vm.envOr("HOODI_AAVE_DATA_PROVIDER", address(0));
        address liveAToken = vm.envOr("HOODI_AAVE_ATOKEN", address(0));

        if (
            preferLive && liveCollateral != address(0) && liveAavePool != address(0) && liveAaveProvider != address(0)
                && liveAaveDataProvider != address(0) && liveAToken != address(0)
        ) {
            deps.aaveMode = DependencyMode.Live;
            deps.aavePool = liveAavePool;
            deps.aaveProvider = liveAaveProvider;
            deps.aaveDataProvider = liveAaveDataProvider;
            deps.aToken = liveAToken;
        } else {
            deps.aaveMode = DependencyMode.Mock;
            (deps.aToken, deps.aaveProvider, deps.aaveDataProvider, deps.aavePool) = _deployMockAaveReserve(deps.collateral);
        }

        address liveMorphoFactory = vm.envOr("HOODI_MORPHO_FACTORY", address(0));
        address liveMorphoAdapterRegistry = vm.envOr("HOODI_MORPHO_ADAPTER_REGISTRY", address(0));
        address liveMorphoVault = vm.envOr("HOODI_MORPHO_VAULT", address(0));

        if (
            preferLive && liveCollateral != address(0) && liveMorphoFactory != address(0)
                && liveMorphoAdapterRegistry != address(0)
                && liveMorphoVault != address(0)
        ) {
            deps.morphoMode = DependencyMode.Live;
            deps.morphoVaultFactory = liveMorphoFactory;
            deps.morphoAdapterRegistry = liveMorphoAdapterRegistry;
            deps.morphoVault = liveMorphoVault;
        } else {
            deps.morphoMode = DependencyMode.Mock;
            _startBroadcast();
            deps.morphoVaultFactory = address(new MockMorphoVaultFactory());
            deps.morphoAdapterRegistry = address(new AdapterRegistry(_scriptOwner()));
            deps.morphoVault = address(new MockMorphoVaultHarness(deps.collateral, deps.morphoAdapterRegistry));
            MockMorphoVaultFactory(deps.morphoVaultFactory).setVault(deps.morphoVault, true);
            _stopBroadcast();
        }

        Logs.log(
            string.concat(
                "Deployed Hoodi adapter dependencies",
                "\n    collateral:",
                vm.toString(deps.collateral),
                "\n    aaveMode:",
                deps.aaveMode == DependencyMode.Live ? "live" : "mock",
                "\n    morphoMode:",
                deps.morphoMode == DependencyMode.Live ? "live" : "mock"
            )
        );
    }

    function _deployMockAaveReserve(address asset)
        internal
        returns (address aToken, address provider, address dataProvider, address pool)
    {
        _startBroadcast();
        MockAaveAToken deployedAToken = new MockAaveAToken(asset);
        MockAavePoolAddressesProvider deployedProvider = new MockAavePoolAddressesProvider();
        MockAavePoolDataProvider deployedDataProvider = new MockAavePoolDataProvider();
        MockAavePool deployedPool = new MockAavePool(asset, address(deployedAToken), address(deployedProvider));
        deployedAToken.setPool(address(deployedPool));
        deployedProvider.setPool(address(deployedPool));
        deployedProvider.setPoolDataProvider(address(deployedDataProvider));
        deployedDataProvider.setReserveToken(asset, address(deployedAToken));
        _stopBroadcast();

        aToken = address(deployedAToken);
        provider = address(deployedProvider);
        dataProvider = address(deployedDataProvider);
        pool = address(deployedPool);
    }

    function _scriptOwner() internal view returns (address owner_) {
        (,, address origin) = vm.readCallers();
        return origin == address(0) ? msg.sender : origin;
    }

    function _startBroadcast() internal virtual {
        vm.startBroadcast();
    }

    function _stopBroadcast() internal virtual {
        vm.stopBroadcast();
    }
}
