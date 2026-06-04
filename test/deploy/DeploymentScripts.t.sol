// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";

import {AaveV3AdapterDeployBaseScript} from "../../script/deploy/base/AaveV3AdapterDeployBase.s.sol";
import {DeployAppAdapterBaseScript} from "../../script/deploy/base/DeployAppAdapterBase.s.sol";
import {MorphoVaultV2AdapterDeployBaseScript} from "../../script/deploy/base/MorphoVaultV2AdapterDeployBase.s.sol";
import {V2DeployBaseScript} from "../../script/deploy/base/V2DeployBase.s.sol";
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

contract V2DeployBaseScriptHarness is V2DeployBaseScript {
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

contract AaveV3AdapterDeployBaseScriptHarness is AaveV3AdapterDeployBaseScript {
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

contract MorphoVaultV2AdapterDeployBaseScriptHarness is MorphoVaultV2AdapterDeployBaseScript {
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

    function test_V2DeployDeploysProtocolFeeRegistryAndWhitelistsImplementations() public {
        VaultFactory vaultFactory = new VaultFactory(address(this));
        DelegatorFactory delegatorFactory = new DelegatorFactory(address(this));

        vaultFactory.whitelist(address(new SimpleMigratableEntity(address(vaultFactory))));
        vaultFactory.whitelist(address(new SimpleMigratableEntity(address(vaultFactory))));
        for (uint64 i; i < 4; ++i) {
            delegatorFactory.whitelist(address(new SimpleEntity(address(delegatorFactory), i)));
        }

        V2DeployBaseScriptHarness script = new V2DeployBaseScriptHarness(vaultFactory, delegatorFactory);

        vaultFactory.transferOwnership(address(script));
        delegatorFactory.transferOwnership(address(script));

        V2DeployBaseScript.DeploymentData memory data = script.runBase(owner, owner);

        assertEq(data.protocolFeeRegistry.owner(), owner);
        assertEq(vaultFactory.implementation(3), address(data.vaultV2));
        assertEq(delegatorFactory.implementation(4), address(data.universalDelegator));
        assertEq(VaultV2(address(data.vaultV2)).FACTORY(), address(vaultFactory));
        assertEq(UniversalDelegator(address(data.universalDelegator)).FACTORY(), address(delegatorFactory));
    }

    function test_AdapterDeployBasesDeployFactoryImplementationAndWhitelist() public {
        VaultFactory vaultFactory = new VaultFactory(address(this));
        AaveV3AdapterDeployBaseScriptHarness aaveScript =
            new AaveV3AdapterDeployBaseScriptHarness(address(vaultFactory));
        MorphoVaultV2AdapterDeployBaseScriptHarness morphoScript =
            new MorphoVaultV2AdapterDeployBaseScriptHarness(address(vaultFactory));
        DeployAppAdapterBaseScriptHarness appScript = new DeployAppAdapterBaseScriptHarness(address(vaultFactory));

        AaveV3AdapterDeployBaseScript.DeploymentData memory aave = aaveScript.runBase(
            AaveV3AdapterDeployBaseScript.DeployParams({
                adapterFactoryOwner: owner,
                aavePool: address(0x2001),
                cowSwapSettlement: address(0x2002),
                cowSwapVaultRelayer: address(0x2003),
                merklDistributor: address(0x2004)
            })
        );
        MorphoVaultV2AdapterDeployBaseScript.DeploymentData memory morpho = morphoScript.runBase(
            MorphoVaultV2AdapterDeployBaseScript.DeployParams({
                adapterFactoryOwner: owner,
                morphoVaultFactory: address(0x3001),
                morphoAdapterRegistry: address(0x3002),
                cowSwapSettlement: address(0x3003),
                cowSwapVaultRelayer: address(0x3004),
                merklDistributor: address(0x3005)
            })
        );
        DeployAppAdapterBaseScript.DeploymentData memory app = appScript.runBase(
            DeployAppAdapterBaseScript.DeployParams({
                adapterFactoryOwner: owner,
                cowSwapSettlement: address(0x4001),
                cowSwapVaultRelayer: address(0x4002),
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
}
