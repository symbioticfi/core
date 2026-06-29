// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {DeployAaveV3AdapterBase} from "../../script/adapters/base/DeployAaveV3AdapterBase.sol";
import {DeployAppAdapterBase} from "../../script/adapters/base/DeployAppAdapterBase.sol";
import {DeployERC4626AdapterBase} from "../../script/adapters/base/DeployERC4626AdapterBase.sol";
import {DeployEulerAdapterBase} from "../../script/adapters/base/DeployEulerAdapterBase.sol";
import {DeployLiquidLaneAdapterBase} from "../../script/adapters/base/DeployLiquidLaneAdapterBase.sol";
import {DeployMorphoVaultV2AdapterBase} from "../../script/adapters/base/DeployMorphoVaultV2AdapterBase.sol";
import {DeployRestakingAppAdapterBase} from "../../script/adapters/base/DeployRestakingAppAdapterBase.sol";
import {DeployThreeFAdapterBase} from "../../script/adapters/base/DeployThreeFAdapterBase.sol";
import {DeployAaveV3AdapterBaseScript} from "../../script/deploy/base/DeployAaveV3AdapterBase.s.sol";
import {DeployAppAdapterBaseScript} from "../../script/deploy/base/DeployAppAdapterBase.s.sol";
import {DeployMorphoVaultV2AdapterBaseScript} from "../../script/deploy/base/DeployMorphoVaultV2AdapterBase.s.sol";
import {DeployV2BaseScript} from "../../script/deploy/base/DeployV2Base.s.sol";
import {SymbioticCoreConstants} from "../integration/SymbioticCoreConstants.sol";
import "../integration/SymbioticCoreImports.sol";

import {AaveV3Adapter} from "../../src/contracts/adapters/AaveV3Adapter.sol";
import {AppAdapter} from "../../src/contracts/adapters/AppAdapter.sol";
import {ERC4626Adapter} from "../../src/contracts/adapters/ERC4626Adapter.sol";
import {EulerAdapter} from "../../src/contracts/adapters/EulerAdapter.sol";
import {LiquidLaneAdapter} from "../../src/contracts/adapters/LiquidLaneAdapter.sol";
import {MorphoVaultV2Adapter} from "../../src/contracts/adapters/MorphoVaultV2Adapter.sol";
import {RestakingAppAdapter} from "../../src/contracts/adapters/RestakingAppAdapter.sol";
import {ThreeFAdapter} from "../../src/contracts/adapters/ThreeFAdapter.sol";
import {DelegatorFactory} from "../../src/contracts/DelegatorFactory.sol";
import {VaultFactory} from "../../src/contracts/VaultFactory.sol";
import {UniversalDelegator} from "../../src/contracts/delegator/UniversalDelegator.sol";
import {VaultV2} from "../../src/contracts/vault/VaultV2.sol";
import {ICoWSwapSettlement} from "../../src/interfaces/adapters/common/ICoWSwapConverter.sol";
import {IMigratablesFactory} from "../../src/interfaces/common/IMigratablesFactory.sol";
import {UNIVERSAL_DELEGATOR_VERSION} from "../../src/interfaces/delegator/IUniversalDelegator.sol";
import {SimpleEntity} from "../mocks/SimpleEntity.sol";
import {SimpleMigratableEntity} from "../mocks/SimpleMigratableEntity.sol";

contract DeployV2BaseScriptHarness is DeployV2BaseScript {
    SymbioticCoreConstants.Core internal _testCore;

    constructor(VaultFactory vaultFactory, DelegatorFactory delegatorFactory) {
        _testCore.vaultFactory = ISymbioticVaultFactory(address(vaultFactory));
        _testCore.delegatorFactory = ISymbioticDelegatorFactory(address(delegatorFactory));
    }

    function _startBroadcast() internal override {}

    function _stopBroadcast() internal override {}

    function _scriptOwner() internal view override returns (address) {
        return address(this);
    }

    function _core() internal view override returns (SymbioticCoreConstants.Core memory) {
        return _testCore;
    }
}

contract DeployAaveV3AdapterBaseScriptHarness is DeployAaveV3AdapterBaseScript {
    address internal immutable _vaultFactory;

    constructor(address vaultFactory) {
        _vaultFactory = vaultFactory;
    }

    function _startBroadcast() internal override {}

    function _stopBroadcast() internal override {}

    function _coreVaultFactory() internal view override returns (address) {
        return _vaultFactory;
    }

    function _scriptOwner() internal view override returns (address) {
        return address(this);
    }
}

contract DeployMorphoVaultV2AdapterBaseScriptHarness is DeployMorphoVaultV2AdapterBaseScript {
    address internal immutable _vaultFactory;

    constructor(address vaultFactory) {
        _vaultFactory = vaultFactory;
    }

    function _startBroadcast() internal override {}

    function _stopBroadcast() internal override {}

    function _coreVaultFactory() internal view override returns (address) {
        return _vaultFactory;
    }

    function _scriptOwner() internal view override returns (address) {
        return address(this);
    }
}

contract DeployAppAdapterBaseScriptHarness is DeployAppAdapterBaseScript {
    address internal immutable _vaultFactory;

    constructor(address vaultFactory) {
        _vaultFactory = vaultFactory;
    }

    function _startBroadcast() internal override {}

    function _stopBroadcast() internal override {}

    function _coreVaultFactory() internal view override returns (address) {
        return _vaultFactory;
    }

    function _scriptOwner() internal view override returns (address) {
        return address(this);
    }
}

contract DeployAaveV3AdapterBaseHarness is DeployAaveV3AdapterBase {
    address internal immutable _vaultFactory;

    constructor(address vaultFactory) {
        _vaultFactory = vaultFactory;
    }

    function _startBroadcast() internal override {}

    function _stopBroadcast() internal override {}

    function _coreVaultFactory() internal view override returns (address) {
        return _vaultFactory;
    }

    function _scriptOwner() internal view override returns (address) {
        return address(this);
    }
}

contract DeployAppAdapterBaseHarness is DeployAppAdapterBase {
    address internal immutable _vaultFactory;

    constructor(address vaultFactory) {
        _vaultFactory = vaultFactory;
    }

    function _startBroadcast() internal override {}

    function _stopBroadcast() internal override {}

    function _coreVaultFactory() internal view override returns (address) {
        return _vaultFactory;
    }

    function _scriptOwner() internal view override returns (address) {
        return address(this);
    }
}

contract DeployERC4626AdapterBaseHarness is DeployERC4626AdapterBase {
    address internal immutable _vaultFactory;

    constructor(address vaultFactory) {
        _vaultFactory = vaultFactory;
    }

    function _startBroadcast() internal override {}

    function _stopBroadcast() internal override {}

    function _coreVaultFactory() internal view override returns (address) {
        return _vaultFactory;
    }

    function _scriptOwner() internal view override returns (address) {
        return address(this);
    }
}

contract DeployEulerAdapterBaseHarness is DeployEulerAdapterBase {
    address internal immutable _vaultFactory;

    constructor(address vaultFactory) {
        _vaultFactory = vaultFactory;
    }

    function _startBroadcast() internal override {}

    function _stopBroadcast() internal override {}

    function _coreVaultFactory() internal view override returns (address) {
        return _vaultFactory;
    }

    function _scriptOwner() internal view override returns (address) {
        return address(this);
    }
}

contract DeployLiquidLaneAdapterBaseHarness is DeployLiquidLaneAdapterBase {
    address internal immutable _vaultFactory;

    constructor(address vaultFactory) {
        _vaultFactory = vaultFactory;
    }

    function _startBroadcast() internal override {}

    function _stopBroadcast() internal override {}

    function _coreVaultFactory() internal view override returns (address) {
        return _vaultFactory;
    }

    function _scriptOwner() internal view override returns (address) {
        return address(this);
    }
}

contract DeployMorphoVaultV2AdapterBaseHarness is DeployMorphoVaultV2AdapterBase {
    address internal immutable _vaultFactory;

    constructor(address vaultFactory) {
        _vaultFactory = vaultFactory;
    }

    function _startBroadcast() internal override {}

    function _stopBroadcast() internal override {}

    function _coreVaultFactory() internal view override returns (address) {
        return _vaultFactory;
    }

    function _scriptOwner() internal view override returns (address) {
        return address(this);
    }
}

contract DeployRestakingAppAdapterBaseHarness is DeployRestakingAppAdapterBase {
    address internal immutable _vaultFactory;

    constructor(address vaultFactory) {
        _vaultFactory = vaultFactory;
    }

    function _startBroadcast() internal override {}

    function _stopBroadcast() internal override {}

    function _coreVaultFactory() internal view override returns (address) {
        return _vaultFactory;
    }

    function _scriptOwner() internal view override returns (address) {
        return address(this);
    }
}

contract DeployThreeFAdapterBaseHarness is DeployThreeFAdapterBase {
    address internal immutable _vaultFactory;

    constructor(address vaultFactory) {
        _vaultFactory = vaultFactory;
    }

    function _startBroadcast() internal override {}

    function _stopBroadcast() internal override {}

    function _coreVaultFactory() internal view override returns (address) {
        return _vaultFactory;
    }

    function _scriptOwner() internal view override returns (address) {
        return address(this);
    }
}

contract DeploymentScriptsTest is Test {
    address internal owner = address(0x1001);

    function test_DeployV2InstallsProtocolFeeRegistryAndDoesNotWhitelistVaultV2() public {
        VaultFactory vaultFactory = new VaultFactory(address(this));
        DelegatorFactory delegatorFactory = new DelegatorFactory(address(this));

        vaultFactory.whitelist(address(new SimpleMigratableEntity(address(vaultFactory))));
        vaultFactory.whitelist(address(new SimpleMigratableEntity(address(vaultFactory))));
        for (uint64 i; i < 4; ++i) {
            delegatorFactory.whitelist(address(new SimpleEntity(address(delegatorFactory), i)));
        }

        DeployV2BaseScriptHarness script = new DeployV2BaseScriptHarness(vaultFactory, delegatorFactory);

        vaultFactory.transferOwnership(address(script));
        delegatorFactory.transferOwnership(address(script));

        DeployV2BaseScript.DeploymentData memory data = script.runBase(owner, owner);

        assertEq(data.protocolFeeRegistry.owner(), owner);
        assertEq(vaultFactory.lastVersion(), 2);
        vm.expectRevert(IMigratablesFactory.InvalidVersion.selector);
        vaultFactory.implementation(3);
        assertEq(
            data.universalDelegatorFactory.implementation(UNIVERSAL_DELEGATOR_VERSION), address(data.universalDelegator)
        );
        assertEq(VaultV2(address(data.vaultV2)).FACTORY(), address(vaultFactory));
        assertEq(
            UniversalDelegator(address(data.universalDelegator)).FACTORY(), address(data.universalDelegatorFactory)
        );
    }

    function test_DeployV2FullParamsDeploysAdapterFactoriesAndWhitelistedImplementations() public {
        VaultFactory vaultFactory = new VaultFactory(address(this));
        DelegatorFactory delegatorFactory = new DelegatorFactory(address(this));

        vaultFactory.whitelist(address(new SimpleMigratableEntity(address(vaultFactory))));
        vaultFactory.whitelist(address(new SimpleMigratableEntity(address(vaultFactory))));
        for (uint64 i; i < 4; ++i) {
            delegatorFactory.whitelist(address(new SimpleEntity(address(delegatorFactory), i)));
        }

        DeployV2BaseScriptHarness script = new DeployV2BaseScriptHarness(vaultFactory, delegatorFactory);

        vaultFactory.transferOwnership(address(script));
        delegatorFactory.transferOwnership(address(script));

        vm.mockCall(address(0x5002), abi.encodeCall(ICoWSwapSettlement.vaultRelayer, ()), abi.encode(address(0x5003)));

        DeployV2BaseScript.DeploymentData memory data = script.runBase(
            DeployV2BaseScript.DeployParams({
                adapterRegistryOwner: owner,
                protocolFeeRegistryOwner: owner,
                adapterFactoryOwner: owner,
                morphoVaultFactory: address(0x5004),
                morphoAdapterRegistry: address(0x5005),
                aavePool: address(0x5006),
                cowSwapSettlement: address(0x5002),
                merklDistributor: address(0x5007),
                networkMiddlewareService: address(0x5008)
            })
        );

        assertEq(vaultFactory.lastVersion(), 2);
        _assertAdapterDeployment(address(data.morphoVaultV2AdapterFactory), address(data.morphoVaultV2Adapter));
        _assertAdapterDeployment(address(data.aaveV3AdapterFactory), address(data.aaveV3Adapter));
        _assertAdapterDeployment(address(data.appAdapterFactory), address(data.appAdapter));
        _assertAdapterDeployment(address(data.restakingAppAdapterFactory), address(data.restakingAppAdapter));

        assertEq(data.morphoVaultV2AdapterFactory.owner(), owner);
        assertEq(data.aaveV3AdapterFactory.owner(), owner);
        assertEq(data.appAdapterFactory.owner(), owner);
        assertEq(data.restakingAppAdapterFactory.owner(), owner);
        assertEq(
            MorphoVaultV2Adapter(address(data.morphoVaultV2Adapter)).FACTORY(),
            address(data.morphoVaultV2AdapterFactory)
        );
        assertEq(AaveV3Adapter(address(data.aaveV3Adapter)).FACTORY(), address(data.aaveV3AdapterFactory));
        assertEq(AppAdapter(address(data.appAdapter)).FACTORY(), address(data.appAdapterFactory));
        assertEq(
            RestakingAppAdapter(address(data.restakingAppAdapter)).FACTORY(), address(data.restakingAppAdapterFactory)
        );
    }

    function test_AdapterDeployBasesDeployFactoryImplementationAndWhitelist() public {
        VaultFactory vaultFactory = new VaultFactory(address(this));
        DeployAaveV3AdapterBaseScriptHarness aaveScript =
            new DeployAaveV3AdapterBaseScriptHarness(address(vaultFactory));
        DeployMorphoVaultV2AdapterBaseScriptHarness morphoScript =
            new DeployMorphoVaultV2AdapterBaseScriptHarness(address(vaultFactory));
        DeployAppAdapterBaseScriptHarness appScript = new DeployAppAdapterBaseScriptHarness(address(vaultFactory));

        vm.mockCall(address(0x2002), abi.encodeCall(ICoWSwapSettlement.vaultRelayer, ()), abi.encode(address(0x2003)));
        vm.mockCall(address(0x3003), abi.encodeCall(ICoWSwapSettlement.vaultRelayer, ()), abi.encode(address(0x3004)));
        vm.mockCall(address(0x4001), abi.encodeCall(ICoWSwapSettlement.vaultRelayer, ()), abi.encode(address(0x4002)));

        DeployAaveV3AdapterBaseScript.DeploymentData memory aave = aaveScript.runBase(
            DeployAaveV3AdapterBaseScript.DeployParams({
                adapterFactoryOwner: owner,
                aavePool: address(0x2001),
                cowSwapSettlement: address(0x2002),
                merklDistributor: address(0x2004)
            })
        );
        DeployMorphoVaultV2AdapterBaseScript.DeploymentData memory morpho = morphoScript.runBase(
            DeployMorphoVaultV2AdapterBaseScript.DeployParams({
                adapterFactoryOwner: owner,
                morphoVaultFactory: address(0x3001),
                morphoAdapterRegistry: address(0x3002),
                cowSwapSettlement: address(0x3003),
                merklDistributor: address(0x3005)
            })
        );
        DeployAppAdapterBaseScript.DeploymentData memory app = appScript.runBase(
            DeployAppAdapterBaseScript.DeployParams({
                adapterFactoryOwner: owner,
                cowSwapSettlement: address(0x4001),
                networkMiddlewareService: address(0x4003)
            })
        );

        assertEq(AaveV3Adapter(aave.adapterImplementation).FACTORY(), aave.adapterFactory);
        assertEq(MorphoVaultV2Adapter(morpho.adapterImplementation).FACTORY(), morpho.adapterFactory);
        assertEq(AppAdapter(app.adapterImplementation).FACTORY(), app.adapterFactory);
        assertEq(IMigratablesFactory(aave.adapterFactory).implementation(1), aave.adapterImplementation);
        assertEq(IMigratablesFactory(morpho.adapterFactory).implementation(1), morpho.adapterImplementation);
        assertEq(IMigratablesFactory(app.adapterFactory).implementation(1), app.adapterImplementation);
    }

    function test_AdapterScriptsDeployAllAdapterFactoriesAndImplementations() public {
        VaultFactory vaultFactory = new VaultFactory(address(this));

        vm.mockCall(address(0x5002), abi.encodeCall(ICoWSwapSettlement.vaultRelayer, ()), abi.encode(address(0x5003)));
        vm.mockCall(address(0x6002), abi.encodeCall(ICoWSwapSettlement.vaultRelayer, ()), abi.encode(address(0x6003)));
        vm.mockCall(address(0x7002), abi.encodeCall(ICoWSwapSettlement.vaultRelayer, ()), abi.encode(address(0x7003)));
        vm.mockCall(address(0x8002), abi.encodeCall(ICoWSwapSettlement.vaultRelayer, ()), abi.encode(address(0x8003)));
        vm.mockCall(address(0x9002), abi.encodeCall(ICoWSwapSettlement.vaultRelayer, ()), abi.encode(address(0x9003)));
        vm.mockCall(address(0xA002), abi.encodeCall(ICoWSwapSettlement.vaultRelayer, ()), abi.encode(address(0xA003)));

        DeployAaveV3AdapterBase.DeploymentData memory aave = new DeployAaveV3AdapterBaseHarness(address(vaultFactory))
            .runBase(
                DeployAaveV3AdapterBase.DeployParams({
                adapterFactoryOwner: owner,
                aavePool: address(0x5001),
                cowSwapSettlement: address(0x5002),
                merklDistributor: address(0x5004)
            })
            );
        DeployAppAdapterBase.DeploymentData memory app = new DeployAppAdapterBaseHarness(address(vaultFactory))
            .runBase(
                DeployAppAdapterBase.DeployParams({
                adapterFactoryOwner: owner,
                cowSwapSettlement: address(0x6002),
                networkMiddlewareService: address(0x6004)
            })
            );
        DeployERC4626AdapterBase.DeploymentData memory erc4626 = new DeployERC4626AdapterBaseHarness(
                address(vaultFactory)
            )
            .runBase(
                DeployERC4626AdapterBase.DeployParams({
                adapterFactoryOwner: owner, cowSwapSettlement: address(0x7002), merklDistributor: address(0x7004)
            })
            );
        DeployEulerAdapterBase.DeploymentData memory euler = new DeployEulerAdapterBaseHarness(address(vaultFactory))
            .runBase(
                DeployEulerAdapterBase.DeployParams({
                adapterFactoryOwner: owner,
                eulerLendVaultFactory: address(0x8001),
                cowSwapSettlement: address(0x8002),
                merklDistributor: address(0x8004)
            })
            );
        DeployLiquidLaneAdapterBase.DeploymentData memory liquidLane = new DeployLiquidLaneAdapterBaseHarness(
                address(vaultFactory)
            )
            .runBase(
                DeployLiquidLaneAdapterBase.DeployParams({adapterFactoryOwner: owner, accountRegistry: address(0xB001)})
            );
        DeployMorphoVaultV2AdapterBase.DeploymentData memory morpho = new DeployMorphoVaultV2AdapterBaseHarness(
                address(vaultFactory)
            )
            .runBase(
                DeployMorphoVaultV2AdapterBase.DeployParams({
                adapterFactoryOwner: owner,
                morphoVaultFactory: address(0x9001),
                morphoAdapterRegistry: address(0x9004),
                cowSwapSettlement: address(0x9002),
                merklDistributor: address(0x9005)
            })
            );
        DeployRestakingAppAdapterBase.DeploymentData memory restaking = new DeployRestakingAppAdapterBaseHarness(
                address(vaultFactory)
            )
            .runBase(
                DeployRestakingAppAdapterBase.DeployParams({
                adapterFactoryOwner: owner,
                cowSwapSettlement: address(0xA002),
                networkMiddlewareService: address(0xA004)
            })
            );
        DeployThreeFAdapterBase.DeploymentData memory threeF = new DeployThreeFAdapterBaseHarness(address(vaultFactory))
            .runBase(
                DeployThreeFAdapterBase.DeployParams({
                adapterFactoryOwner: owner, requestWhitelist: address(0xC001)
            })
            );

        _assertAdapterDeployment(aave.adapterFactory, aave.adapterImplementation);
        _assertAdapterDeployment(app.adapterFactory, app.adapterImplementation);
        _assertAdapterDeployment(erc4626.adapterFactory, erc4626.adapterImplementation);
        _assertAdapterDeployment(euler.adapterFactory, euler.adapterImplementation);
        _assertAdapterDeployment(liquidLane.adapterFactory, liquidLane.adapterImplementation);
        _assertAdapterDeployment(morpho.adapterFactory, morpho.adapterImplementation);
        _assertAdapterDeployment(restaking.adapterFactory, restaking.adapterImplementation);
        _assertAdapterDeployment(threeF.adapterFactory, threeF.adapterImplementation);

        assertEq(AaveV3Adapter(aave.adapterImplementation).FACTORY(), aave.adapterFactory);
        assertEq(AppAdapter(app.adapterImplementation).FACTORY(), app.adapterFactory);
        assertEq(ERC4626Adapter(erc4626.adapterImplementation).FACTORY(), erc4626.adapterFactory);
        assertEq(EulerAdapter(euler.adapterImplementation).FACTORY(), euler.adapterFactory);
        assertEq(LiquidLaneAdapter(liquidLane.adapterImplementation).FACTORY(), liquidLane.adapterFactory);
        assertEq(MorphoVaultV2Adapter(morpho.adapterImplementation).FACTORY(), morpho.adapterFactory);
        assertEq(RestakingAppAdapter(restaking.adapterImplementation).FACTORY(), restaking.adapterFactory);
        assertEq(ThreeFAdapter(threeF.adapterImplementation).FACTORY(), threeF.adapterFactory);
        assertEq(ThreeFAdapter(threeF.adapterImplementation).REQUEST_WHITELIST(), address(0xC001));
    }

    function _assertAdapterDeployment(address adapterFactory, address adapterImplementation) internal view {
        assertEq(IMigratablesFactory(adapterFactory).implementation(1), adapterImplementation);
    }
}
