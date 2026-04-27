// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {UpgradeableBeacon} from "@solady/src/utils/UpgradeableBeacon.sol";

import {AdapterRegistry} from "../../../src/contracts/AdapterRegistry.sol";
import {AaveV3Adapter} from "../../../src/contracts/vault/adapters/AaveV3Adapter.sol";
import {MorphoVaultV2Adapter} from "../../../src/contracts/vault/adapters/MorphoVaultV2Adapter.sol";

import {IEntity} from "../../../src/interfaces/common/IEntity.sol";
import {IFactory} from "../../../src/interfaces/common/IFactory.sol";
import {IMigratableEntity} from "../../../src/interfaces/common/IMigratableEntity.sol";
import {IMigratablesFactory} from "../../../src/interfaces/common/IMigratablesFactory.sol";
import {IRegistry} from "../../../src/interfaces/common/IRegistry.sol";
import {UNIVERSAL_DELEGATOR_TYPE} from "../../../src/interfaces/delegator/IUniversalDelegator.sol";
import {UNIVERSAL_SLASHER_TYPE} from "../../../src/interfaces/slasher/IUniversalSlasher.sol";
import {VAULT_V2_VERSION} from "../../../src/interfaces/vault/IVaultV2.sol";
import {IAaveV3Pool} from "../../../src/interfaces/vault/adapters/aave_v3_adapter/IAaveV3AdapterDependencies.sol";

import {SymbioticCoreConstants} from "../SymbioticCoreConstants.sol";
import {
    ISymbioticDelegatorFactory,
    ISymbioticMetadataService,
    ISymbioticNetworkMiddlewareService,
    ISymbioticNetworkRegistry,
    ISymbioticOperatorRegistry,
    ISymbioticOptInService,
    ISymbioticSlasherFactory,
    ISymbioticVaultConfigurator,
    ISymbioticVaultFactory
} from "../SymbioticCoreImports.sol";

import {ScriptBase} from "../../../script/utils/ScriptBase.s.sol";
import {ScriptBaseHarness} from "./ScriptBaseHarness.s.sol";

import {V2DeployBaseScript} from "../../../script/deploy/base/V2DeployBase.s.sol";
import {V2UpgradeBaseScript} from "../../../script/upgrade/base/V2UpgradeBase.s.sol";
import {V2WhitelistAdaptersBaseScript} from "../../../script/upgrade/base/V2WhitelistAdaptersBase.s.sol";

import {AaveV3AdapterDeployBaseScript} from "../../../script/deploy/base/AaveV3AdapterDeployBase.s.sol";
import {AaveV3MocksDeployBaseScript} from "../../../script/deploy/testnet/base/AaveV3MocksDeployBase.s.sol";

import {MorphoVaultV2AdapterDeployBaseScript} from "../../../script/deploy/base/MorphoVaultV2AdapterDeployBase.s.sol";
import {
    MorphoVaultV2MocksDeployBaseScript
} from "../../../script/deploy/testnet/base/MorphoVaultV2MocksDeployBase.s.sol";

import {
    MockAaveAToken,
    MockAaveATokenUpgradeable,
    MockAavePoolAddressesProvider,
    MockAavePoolDataProvider,
    MockAavePoolUpgradeable,
    MockHoodiTokenUpgradeable,
    MockMorphoVaultFactory,
    MockMorphoVaultFactoryUpgradeable,
    MockMorphoVaultHarness
} from "../../mocks/HoodiScenarioProtocolMocks.sol";
import {MockRewards} from "../../mocks/MockRewards.sol";

contract MockCoreFactory {
    uint64 public immutable totalTypes;

    constructor(uint64 totalTypes_) {
        totalTypes = totalTypes_;
    }
}

contract V2DeployScriptHarness is V2DeployBaseScript {
    address internal immutable broadcaster;
    SymbioticCoreConstants.Core internal core;

    constructor(address broadcaster_, SymbioticCoreConstants.Core memory core_) {
        broadcaster = broadcaster_;
        core = core_;
    }

    function _startBroadcast() internal override {
        vm.startBroadcast(broadcaster);
    }

    function _stopBroadcast() internal override {
        vm.stopBroadcast();
    }

    function _core() internal view override returns (SymbioticCoreConstants.Core memory) {
        return core;
    }
}

contract AaveV3MocksDeployScriptHarness is AaveV3MocksDeployBaseScript {
    address internal immutable broadcaster;

    constructor(address broadcaster_) {
        broadcaster = broadcaster_;
    }

    function _startBroadcast() internal override {
        vm.startBroadcast(broadcaster);
    }

    function _stopBroadcast() internal override {
        vm.stopBroadcast();
    }
}

contract MorphoVaultV2MocksDeployScriptHarness is MorphoVaultV2MocksDeployBaseScript {
    address internal immutable broadcaster;

    constructor(address broadcaster_) {
        broadcaster = broadcaster_;
    }

    function _startBroadcast() internal override {
        vm.startBroadcast(broadcaster);
    }

    function _stopBroadcast() internal override {
        vm.stopBroadcast();
    }
}

contract AaveV3AdapterDeployScriptHarness is AaveV3AdapterDeployBaseScript {
    address internal immutable broadcaster;

    constructor(address broadcaster_) {
        broadcaster = broadcaster_;
    }

    function _startBroadcast() internal override {
        vm.startBroadcast(broadcaster);
    }

    function _stopBroadcast() internal override {
        vm.stopBroadcast();
    }
}

contract MorphoVaultV2AdapterDeployScriptHarness is MorphoVaultV2AdapterDeployBaseScript {
    address internal immutable broadcaster;

    constructor(address broadcaster_) {
        broadcaster = broadcaster_;
    }

    function _startBroadcast() internal override {
        vm.startBroadcast(broadcaster);
    }

    function _stopBroadcast() internal override {
        vm.stopBroadcast();
    }
}

contract V2UpgradeScriptHarness is V2UpgradeBaseScript, ScriptBaseHarness {
    constructor(address broadcaster_) ScriptBaseHarness(broadcaster_) {}

    function sendTransaction(address target, bytes memory data) public override(ScriptBase, ScriptBaseHarness) {
        ScriptBaseHarness.sendTransaction(target, data);
    }
}

contract V2WhitelistAdaptersScriptHarness is V2WhitelistAdaptersBaseScript, ScriptBaseHarness {
    constructor(address broadcaster_) ScriptBaseHarness(broadcaster_) {}

    function sendTransaction(address target, bytes memory data) public override(ScriptBase, ScriptBaseHarness) {
        ScriptBaseHarness.sendTransaction(target, data);
    }
}

contract V2DeploymentScriptsTest is Test {
    bytes32 internal constant ERC1967_IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    bytes32 internal constant ERC1967_ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    address internal constant HOODI_VAULT_FACTORY = 0x407A039D94948484D356eFB765b3c74382A050B4;
    address internal constant HOODI_DELEGATOR_FACTORY = 0x890CA3f95E0f40a79885B7400926544B2214B03f;
    address internal constant HOODI_SLASHER_FACTORY = 0xbf34bf75bb779c383267736c53a4ae86ac7bB299;

    address internal broadcaster;
    address internal adapterOwner;
    address internal feeRegistry;
    address internal curatorRegistry;
    address internal rewards;

    function setUp() public {
        vm.chainId(560_048);

        broadcaster = makeAddr("broadcaster");
        adapterOwner = makeAddr("adapterOwner");
        feeRegistry = makeAddr("feeRegistry");
        curatorRegistry = makeAddr("curatorRegistry");
        rewards = address(new MockRewards());
    }

    function test_V2DeployBaseScriptDeploysCoreImplementationsWithCustomValues() public {
        SymbioticCoreConstants.Core memory core = _localCore();
        V2DeployScriptHarness script = new V2DeployScriptHarness(broadcaster, core);

        V2DeployBaseScript.DeploymentData memory data = script.runBase(adapterOwner, feeRegistry, rewards);

        assertEq(address(data.core.vaultFactory), address(core.vaultFactory), "vault factory mismatch");
        assertEq(address(data.core.delegatorFactory), address(core.delegatorFactory), "delegator factory mismatch");
        assertEq(address(data.core.slasherFactory), address(core.slasherFactory), "slasher factory mismatch");
        assertTrue(address(data.adapterRegistry).code.length > 0, "missing adapter registry code");
        assertTrue(address(data.vaultV2Migrate).code.length > 0, "missing vaultV2Migrate code");
        assertTrue(address(data.vaultV2).code.length > 0, "missing vaultV2 code");
        assertTrue(address(data.universalDelegator).code.length > 0, "missing universalDelegator code");
        assertTrue(address(data.universalSlasher).code.length > 0, "missing universalSlasher code");
        assertEq(Ownable(address(data.adapterRegistry)).owner(), adapterOwner, "adapter registry owner mismatch");
        assertEq(
            IMigratableEntity(address(data.vaultV2)).FACTORY(), address(core.vaultFactory), "vault factory mismatch"
        );
        assertEq(
            IEntity(address(data.universalDelegator)).FACTORY(),
            address(core.delegatorFactory),
            "delegator factory mismatch"
        );
        assertEq(IEntity(address(data.universalDelegator)).TYPE(), UNIVERSAL_DELEGATOR_TYPE, "delegator type mismatch");
        assertEq(
            IEntity(address(data.universalSlasher)).FACTORY(), address(core.slasherFactory), "slasher factory mismatch"
        );
        assertEq(IEntity(address(data.universalSlasher)).TYPE(), UNIVERSAL_SLASHER_TYPE, "slasher type mismatch");
    }

    function test_V2UpgradeBaseScriptBuildsWhitelistTransactionsWithCustomImplementations() public {
        V2UpgradeScriptHarness script = new V2UpgradeScriptHarness(broadcaster);
        address vaultV2 = makeAddr("vaultV2");
        address universalDelegator = makeAddr("universalDelegator");
        address universalSlasher = makeAddr("universalSlasher");
        _mockV2UpgradePostChecks(vaultV2, universalDelegator, universalSlasher);

        vm.expectCall(HOODI_VAULT_FACTORY, abi.encodeCall(IMigratablesFactory.whitelist, (vaultV2)));
        (bytes memory whitelistVaultData, address whitelistVaultTarget) = script.whitelistVaultV2(vaultV2);

        vm.expectCall(HOODI_DELEGATOR_FACTORY, abi.encodeCall(IFactory.whitelist, (universalDelegator)));
        (bytes memory whitelistDelegatorData, address whitelistDelegatorTarget) =
            script.whitelistUniversalDelegator(universalDelegator);

        vm.expectCall(HOODI_SLASHER_FACTORY, abi.encodeCall(IFactory.whitelist, (universalSlasher)));
        (bytes memory whitelistSlasherData, address whitelistSlasherTarget) =
            script.whitelistUniversalSlasher(universalSlasher);

        assertEq(whitelistVaultTarget, HOODI_VAULT_FACTORY, "vault target mismatch");
        assertEq(whitelistVaultData, abi.encodeCall(IMigratablesFactory.whitelist, (vaultV2)), "vault data mismatch");
        assertEq(whitelistDelegatorTarget, HOODI_DELEGATOR_FACTORY, "delegator target mismatch");
        assertEq(
            whitelistDelegatorData, abi.encodeCall(IFactory.whitelist, (universalDelegator)), "delegator data mismatch"
        );
        assertEq(whitelistSlasherTarget, HOODI_SLASHER_FACTORY, "slasher target mismatch");
        assertEq(whitelistSlasherData, abi.encodeCall(IFactory.whitelist, (universalSlasher)), "slasher data mismatch");
    }

    function test_AaveV3MocksDeployBaseScriptDeploysLinkedReserve() public {
        AaveV3MocksDeployScriptHarness script = new AaveV3MocksDeployScriptHarness(broadcaster);
        AaveV3MocksDeployBaseScript.DeploymentData memory data = script.runBase(address(0));

        assertTrue(data.collateral.code.length > 0, "missing collateral code");
        assertTrue(data.aavePool.code.length > 0, "missing pool code");
        assertTrue(data.aaveProvider.code.length > 0, "missing provider code");
        assertTrue(data.aaveDataProvider.code.length > 0, "missing data provider code");
        assertTrue(data.aToken.code.length > 0, "missing aToken code");
        _assertProxy(data.collateral, data.collateralImplementation, data.collateralProxyAdmin, broadcaster);
        _assertProxy(data.aavePool, data.aavePoolImplementation, data.aavePoolProxyAdmin, broadcaster);
        _assertProxy(data.aaveProvider, data.aaveProviderImplementation, data.aaveProviderProxyAdmin, broadcaster);
        _assertProxy(
            data.aaveDataProvider, data.aaveDataProviderImplementation, data.aaveDataProviderProxyAdmin, broadcaster
        );
        _assertProxy(data.aToken, data.aTokenImplementation, data.aTokenProxyAdmin, broadcaster);
        assertEq(IAaveV3Pool(data.aavePool).getReserveAToken(data.collateral), data.aToken, "reserve aToken mismatch");
        assertEq(MockAaveAToken(data.aToken).pool(), data.aavePool, "aToken pool mismatch");
        assertEq(MockAavePoolAddressesProvider(data.aaveProvider).getPool(), data.aavePool, "provider pool mismatch");
        assertEq(
            MockAavePoolAddressesProvider(data.aaveProvider).getPoolDataProvider(),
            data.aaveDataProvider,
            "provider data provider mismatch"
        );
        (address reserveAToken,,) =
            MockAavePoolDataProvider(data.aaveDataProvider).getReserveTokensAddresses(data.collateral);
        assertEq(reserveAToken, data.aToken, "data provider aToken mismatch");

        (,, address secondCollateral) = _deployTokenProxy("Second Aave Collateral", address(this));
        (address secondATokenImplementation, address secondATokenProxyAdmin, address secondAToken) =
            _deployATokenProxy(secondCollateral);
        MockAaveATokenUpgradeable(secondAToken).setPool(data.aavePool);
        MockAavePoolUpgradeable(data.aavePool).setReserveToken(secondCollateral, secondAToken);
        MockAavePoolDataProvider(data.aaveDataProvider).setReserveToken(secondCollateral, secondAToken);

        _assertProxy(secondAToken, secondATokenImplementation, secondATokenProxyAdmin, address(this));
        assertEq(
            IAaveV3Pool(data.aavePool).getReserveAToken(secondCollateral),
            secondAToken,
            "second reserve aToken mismatch"
        );
        (address secondReserveAToken,,) =
            MockAavePoolDataProvider(data.aaveDataProvider).getReserveTokensAddresses(secondCollateral);
        assertEq(secondReserveAToken, secondAToken, "second data provider aToken mismatch");

        IERC20(secondCollateral).approve(data.aavePool, 100);
        IAaveV3Pool(data.aavePool).supply(secondCollateral, 100, address(this), 0);
        assertEq(MockAaveATokenUpgradeable(secondAToken).balanceOf(address(this)), 100, "second supply aToken mismatch");
        assertEq(
            IAaveV3Pool(data.aavePool).getVirtualUnderlyingBalance(secondCollateral),
            100,
            "second virtual balance mismatch"
        );

        assertEq(
            IAaveV3Pool(data.aavePool).withdraw(secondCollateral, 40, address(this)), 40, "second withdraw mismatch"
        );
        assertEq(
            MockAaveATokenUpgradeable(secondAToken).balanceOf(address(this)),
            60,
            "second withdraw aToken balance mismatch"
        );
    }

    function test_MorphoVaultV2MocksDeployBaseScriptDeploysRegisteredVault() public {
        MorphoVaultV2MocksDeployScriptHarness script = new MorphoVaultV2MocksDeployScriptHarness(broadcaster);
        MorphoVaultV2MocksDeployBaseScript.DeploymentData memory data = script.runBase(
            MorphoVaultV2MocksDeployBaseScript.DeployParams({
                adapterRegistryOwner: adapterOwner, collateral: address(0)
            })
        );

        assertTrue(data.collateral.code.length > 0, "missing collateral code");
        assertTrue(data.morphoVaultFactory.code.length > 0, "missing factory code");
        assertTrue(data.morphoAdapterRegistry.code.length > 0, "missing adapter registry code");
        assertTrue(data.morphoVault.code.length > 0, "missing vault code");
        _assertProxy(data.collateral, data.collateralImplementation, data.collateralProxyAdmin, adapterOwner);
        _assertProxy(
            data.morphoVaultFactory,
            data.morphoVaultFactoryImplementation,
            data.morphoVaultFactoryProxyAdmin,
            adapterOwner
        );
        _assertProxy(
            data.morphoAdapterRegistry,
            data.morphoAdapterRegistryImplementation,
            data.morphoAdapterRegistryProxyAdmin,
            adapterOwner
        );
        _assertProxy(data.morphoVault, data.morphoVaultImplementation, data.morphoVaultProxyAdmin, adapterOwner);
        assertEq(Ownable(data.morphoAdapterRegistry).owner(), adapterOwner, "adapter registry owner mismatch");
        assertTrue(
            MockMorphoVaultFactory(data.morphoVaultFactory).isVaultV2(data.morphoVault), "morpho vault not registered"
        );
        assertEq(
            address(MockMorphoVaultHarness(data.morphoVault).asset()), data.collateral, "morpho vault asset mismatch"
        );
        assertEq(
            MockMorphoVaultHarness(data.morphoVault).adapterRegistry(),
            data.morphoAdapterRegistry,
            "morpho adapter registry mismatch"
        );

        address secondCollateral = makeAddr("secondCollateral");
        (address secondMorphoVaultImplementation, address secondMorphoVault) =
            MockMorphoVaultFactoryUpgradeable(data.morphoVaultFactory).createVault(secondCollateral);
        address secondMorphoVaultProxyAdmin = _proxyAdmin(secondMorphoVault);

        _assertProxy(secondMorphoVault, secondMorphoVaultImplementation, secondMorphoVaultProxyAdmin, adapterOwner);
        assertTrue(
            MockMorphoVaultFactory(data.morphoVaultFactory).isVaultV2(secondMorphoVault),
            "second morpho vault not registered"
        );
        assertEq(
            address(MockMorphoVaultHarness(secondMorphoVault).asset()),
            secondCollateral,
            "second morpho vault asset mismatch"
        );
        assertEq(
            MockMorphoVaultHarness(secondMorphoVault).adapterRegistry(),
            data.morphoAdapterRegistry,
            "second morpho adapter registry mismatch"
        );
    }

    function test_AaveV3AdapterDeployBaseScriptDeploysOwnedAdapter() public {
        AaveV3MocksDeployBaseScript.DeploymentData memory mocks =
            new AaveV3MocksDeployScriptHarness(broadcaster).runBase(address(0));

        AaveV3AdapterDeployScriptHarness script = new AaveV3AdapterDeployScriptHarness(broadcaster);
        AaveV3AdapterDeployBaseScript.DeploymentData memory data = script.runBase(
            AaveV3AdapterDeployBaseScript.DeployParams({
                adapterOwner: adapterOwner, aavePool: mocks.aavePool, curatorRegistry: curatorRegistry, rewards: rewards
            })
        );

        assertTrue(data.accountImplementation.code.length > 0, "missing account implementation code");
        assertTrue(data.beacon.code.length > 0, "missing beacon code");
        assertTrue(data.adapterImplementation.code.length > 0, "missing adapter implementation code");
        assertTrue(data.proxyAdmin.code.length > 0, "missing proxy admin code");
        assertTrue(data.adapter.code.length > 0, "missing adapter code");
        assertEq(_proxyImplementation(data.adapter), data.adapterImplementation, "proxy implementation mismatch");
        assertEq(_proxyAdmin(data.adapter), data.proxyAdmin, "proxy admin mismatch");
        assertEq(Ownable(data.proxyAdmin).owner(), adapterOwner, "proxy admin owner mismatch");
        assertEq(UpgradeableBeacon(data.beacon).implementation(), data.accountImplementation, "beacon impl mismatch");
        assertEq(UpgradeableBeacon(data.beacon).owner(), address(0), "beacon owner mismatch");
        assertEq(AaveV3Adapter(data.adapter).owner(), adapterOwner, "adapter owner mismatch");
        assertEq(AaveV3Adapter(data.adapter).VAULT_FACTORY(), HOODI_VAULT_FACTORY, "vault factory mismatch");
    }

    function test_MorphoVaultV2AdapterDeployBaseScriptDeploysOwnedAdapter() public {
        MorphoVaultV2MocksDeployBaseScript.DeploymentData memory mocks = new MorphoVaultV2MocksDeployScriptHarness(
                broadcaster
            )
            .runBase(
                MorphoVaultV2MocksDeployBaseScript.DeployParams({
                    adapterRegistryOwner: adapterOwner, collateral: address(0)
                })
            );

        MorphoVaultV2AdapterDeployScriptHarness script = new MorphoVaultV2AdapterDeployScriptHarness(broadcaster);
        MorphoVaultV2AdapterDeployBaseScript.DeploymentData memory data = script.runBase(
            MorphoVaultV2AdapterDeployBaseScript.DeployParams({
                adapterOwner: adapterOwner,
                morphoVaultFactory: mocks.morphoVaultFactory,
                morphoAdapterRegistry: mocks.morphoAdapterRegistry,
                curatorRegistry: curatorRegistry,
                rewards: rewards
            })
        );

        assertTrue(data.accountImplementation.code.length > 0, "missing account implementation code");
        assertTrue(data.beacon.code.length > 0, "missing beacon code");
        assertTrue(data.adapterImplementation.code.length > 0, "missing adapter implementation code");
        assertTrue(data.proxyAdmin.code.length > 0, "missing proxy admin code");
        assertTrue(data.adapter.code.length > 0, "missing adapter code");
        assertEq(_proxyImplementation(data.adapter), data.adapterImplementation, "proxy implementation mismatch");
        assertEq(_proxyAdmin(data.adapter), data.proxyAdmin, "proxy admin mismatch");
        assertEq(Ownable(data.proxyAdmin).owner(), adapterOwner, "proxy admin owner mismatch");
        assertEq(UpgradeableBeacon(data.beacon).implementation(), data.accountImplementation, "beacon impl mismatch");
        assertEq(UpgradeableBeacon(data.beacon).owner(), address(0), "beacon owner mismatch");
        assertEq(MorphoVaultV2Adapter(data.adapter).owner(), adapterOwner, "adapter owner mismatch");
        assertEq(MorphoVaultV2Adapter(data.adapter).VAULT_FACTORY(), HOODI_VAULT_FACTORY, "vault factory mismatch");
    }

    function test_V2WhitelistAdaptersBaseScriptWhitelistsSingleAdapter() public {
        AdapterRegistry adapterRegistry = new AdapterRegistry(adapterOwner);
        address adapter = makeAddr("adapter");

        V2WhitelistAdaptersScriptHarness script = new V2WhitelistAdaptersScriptHarness(adapterOwner);
        (bytes memory data, address target) = script.whitelistAdapter(address(adapterRegistry), adapter);

        assertEq(target, address(adapterRegistry), "target mismatch");
        assertEq(data, abi.encodeCall(AdapterRegistry.whitelistAdapter, (adapter)), "calldata mismatch");
        assertTrue(IRegistry(address(adapterRegistry)).isEntity(adapter), "adapter not whitelisted");
        assertEq(IRegistry(address(adapterRegistry)).totalEntities(), 1, "unexpected entity count");
        assertEq(IRegistry(address(adapterRegistry)).entity(0), adapter, "entity mismatch");
    }

    function _proxyImplementation(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, ERC1967_IMPLEMENTATION_SLOT))));
    }

    function _proxyAdmin(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, ERC1967_ADMIN_SLOT))));
    }

    function _assertProxy(address proxy, address implementation, address proxyAdmin, address proxyAdminOwner)
        internal
        view
    {
        assertTrue(implementation.code.length > 0, "missing implementation code");
        assertTrue(proxyAdmin.code.length > 0, "missing proxy admin code");
        assertEq(_proxyImplementation(proxy), implementation, "proxy implementation mismatch");
        assertEq(_proxyAdmin(proxy), proxyAdmin, "proxy admin mismatch");
        assertEq(Ownable(proxyAdmin).owner(), proxyAdminOwner, "proxy admin owner mismatch");
    }

    function _deployATokenProxy(address collateral)
        internal
        returns (address implementation, address proxyAdmin, address proxy)
    {
        implementation = address(new MockAaveATokenUpgradeable());
        proxy = address(
            new TransparentUpgradeableProxy(
                implementation, address(this), abi.encodeCall(MockAaveATokenUpgradeable.initialize, (collateral))
            )
        );
        proxyAdmin = _proxyAdmin(proxy);
    }

    function _deployTokenProxy(string memory name, address recipient)
        internal
        returns (address implementation, address proxyAdmin, address proxy)
    {
        implementation = address(new MockHoodiTokenUpgradeable());
        proxy = address(
            new TransparentUpgradeableProxy(
                implementation, address(this), abi.encodeCall(MockHoodiTokenUpgradeable.initialize, (name, recipient))
            )
        );
        proxyAdmin = _proxyAdmin(proxy);
    }

    function _localCore() internal returns (SymbioticCoreConstants.Core memory core) {
        MockCoreFactory vaultFactory = new MockCoreFactory(0);
        MockCoreFactory delegatorFactory = new MockCoreFactory(UNIVERSAL_DELEGATOR_TYPE);
        MockCoreFactory slasherFactory = new MockCoreFactory(UNIVERSAL_SLASHER_TYPE);

        core = SymbioticCoreConstants.Core({
            vaultFactory: ISymbioticVaultFactory(address(vaultFactory)),
            delegatorFactory: ISymbioticDelegatorFactory(address(delegatorFactory)),
            slasherFactory: ISymbioticSlasherFactory(address(slasherFactory)),
            networkRegistry: ISymbioticNetworkRegistry(makeAddr("networkRegistry")),
            networkMetadataService: ISymbioticMetadataService(address(0)),
            networkMiddlewareService: ISymbioticNetworkMiddlewareService(makeAddr("networkMiddlewareService")),
            operatorRegistry: ISymbioticOperatorRegistry(address(0)),
            operatorMetadataService: ISymbioticMetadataService(address(0)),
            operatorVaultOptInService: ISymbioticOptInService(address(0)),
            operatorNetworkOptInService: ISymbioticOptInService(address(0)),
            vaultConfigurator: ISymbioticVaultConfigurator(address(0))
        });
    }

    function _mockV2UpgradePostChecks(address vaultV2, address universalDelegator, address universalSlasher) internal {
        vm.mockCall(vaultV2, abi.encodeCall(IMigratableEntity.FACTORY, ()), abi.encode(HOODI_VAULT_FACTORY));
        vm.mockCall(
            HOODI_VAULT_FACTORY,
            abi.encodeCall(IMigratablesFactory.implementation, (VAULT_V2_VERSION)),
            abi.encode(vaultV2)
        );
        vm.mockCall(universalDelegator, abi.encodeCall(IEntity.TYPE, ()), abi.encode(UNIVERSAL_DELEGATOR_TYPE));
        vm.mockCall(
            HOODI_DELEGATOR_FACTORY,
            abi.encodeCall(IFactory.implementation, (UNIVERSAL_DELEGATOR_TYPE)),
            abi.encode(universalDelegator)
        );
        vm.mockCall(universalSlasher, abi.encodeCall(IEntity.TYPE, ()), abi.encode(UNIVERSAL_SLASHER_TYPE));
        vm.mockCall(
            HOODI_SLASHER_FACTORY,
            abi.encodeCall(IFactory.implementation, (UNIVERSAL_SLASHER_TYPE)),
            abi.encode(universalSlasher)
        );
    }
}
