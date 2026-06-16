// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {DeployAaveV3AdapterBaseScript} from "../../script/deploy/base/DeployAaveV3AdapterBase.s.sol";
import {DeployAppAdapterBaseScript} from "../../script/deploy/base/DeployAppAdapterBase.s.sol";
import {DeployMorphoVaultV2AdapterBaseScript} from "../../script/deploy/base/DeployMorphoVaultV2AdapterBase.s.sol";
import {DeployV2BaseScript} from "../../script/deploy/base/DeployV2Base.s.sol";
import {SymbioticCoreConstants} from "../integration/SymbioticCoreConstants.sol";
import "../integration/SymbioticCoreImports.sol";

import {AaveV3Adapter} from "../../src/contracts/adapters/AaveV3Adapter.sol";
import {AppAdapter} from "../../src/contracts/adapters/AppAdapter.sol";
import {MorphoVaultV2Adapter} from "../../src/contracts/adapters/MorphoVaultV2Adapter.sol";
import {DelegatorFactory} from "../../src/contracts/DelegatorFactory.sol";
import {VaultFactory} from "../../src/contracts/VaultFactory.sol";
import {UniversalDelegator} from "../../src/contracts/delegator/UniversalDelegator.sol";
import {VaultV2} from "../../src/contracts/vault/VaultV2.sol";
import {IMigratablesFactory} from "../../src/interfaces/common/IMigratablesFactory.sol";
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

contract DeploymentScriptsTest is Test {
    address internal owner = address(0x1001);

    function test_DeployV2InstallsProtocolFeeRegistryAndWhitelistsImplementations() public {
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
        assertEq(vaultFactory.implementation(3), address(data.vaultV2));
        assertEq(delegatorFactory.implementation(4), address(data.universalDelegator));
        assertEq(VaultV2(address(data.vaultV2)).FACTORY(), address(vaultFactory));
        assertEq(UniversalDelegator(address(data.universalDelegator)).FACTORY(), address(delegatorFactory));
    }

    function test_AdapterDeployBasesDeployFactoryImplementationAndWhitelist() public {
        VaultFactory vaultFactory = new VaultFactory(address(this));
        DeployAaveV3AdapterBaseScriptHarness aaveScript =
            new DeployAaveV3AdapterBaseScriptHarness(address(vaultFactory));
        DeployMorphoVaultV2AdapterBaseScriptHarness morphoScript =
            new DeployMorphoVaultV2AdapterBaseScriptHarness(address(vaultFactory));
        DeployAppAdapterBaseScriptHarness appScript = new DeployAppAdapterBaseScriptHarness(address(vaultFactory));

        vm.mockCall(address(0x2002), abi.encodeWithSignature("vaultRelayer()"), abi.encode(address(0x2003)));
        vm.mockCall(address(0x3003), abi.encodeWithSignature("vaultRelayer()"), abi.encode(address(0x3004)));

        DeployAaveV3AdapterBaseScript.DeploymentData memory aave = aaveScript.runBase(
            DeployAaveV3AdapterBaseScript.DeployParams({adapterFactoryOwner: owner, aavePool: address(0x2001)})
        );
        DeployMorphoVaultV2AdapterBaseScript.DeploymentData memory morpho = morphoScript.runBase(
            DeployMorphoVaultV2AdapterBaseScript.DeployParams({
                adapterFactoryOwner: owner, morphoVaultFactory: address(0x3001), morphoAdapterRegistry: address(0x3002)
            })
        );
        DeployAppAdapterBaseScript.DeploymentData memory app = appScript.runBase(
            DeployAppAdapterBaseScript.DeployParams({
                adapterFactoryOwner: owner, networkMiddlewareService: address(0x4003)
            })
        );

        assertEq(AaveV3Adapter(aave.adapterImplementation).FACTORY(), aave.adapterFactory);
        assertEq(MorphoVaultV2Adapter(morpho.adapterImplementation).FACTORY(), morpho.adapterFactory);
        assertEq(AppAdapter(app.adapterImplementation).FACTORY(), app.adapterFactory);
        assertEq(IMigratablesFactory(aave.adapterFactory).implementation(1), aave.adapterImplementation);
        assertEq(IMigratablesFactory(morpho.adapterFactory).implementation(1), morpho.adapterImplementation);
        assertEq(IMigratablesFactory(app.adapterFactory).implementation(1), app.adapterImplementation);
    }
}
