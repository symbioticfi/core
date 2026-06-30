// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {Logs} from "../../utils/Logs.sol";
import {SymbioticCoreConstants} from "../../../test/integration/SymbioticCoreConstants.sol";

import {AdapterRegistry} from "../../../src/contracts/AdapterRegistry.sol";
import {ProtocolFeeRegistry} from "../../../src/contracts/ProtocolFeeRegistry.sol";
import {AdapterFactory} from "../../../src/contracts/adapters/AdapterFactory.sol";
import {AaveV3Adapter} from "../../../src/contracts/adapters/AaveV3Adapter.sol";
import {AppAdapter} from "../../../src/contracts/adapters/AppAdapter.sol";
import {MorphoVaultV2Adapter} from "../../../src/contracts/adapters/MorphoVaultV2Adapter.sol";
import {RestakingAppAdapter} from "../../../src/contracts/adapters/RestakingAppAdapter.sol";
import {UniversalDelegator} from "../../../src/contracts/delegator/UniversalDelegator.sol";
import {UniversalDelegatorFactory} from "../../../src/contracts/UniversalDelegatorFactory.sol";
import {VaultV2} from "../../../src/contracts/vault/VaultV2.sol";
import {WithdrawalQueue} from "../../../src/contracts/vault/WithdrawalQueue.sol";
import {WithdrawalQueueFactory} from "../../../src/contracts/WithdrawalQueueFactory.sol";

import {IMigratableEntity} from "../../../src/interfaces/common/IMigratableEntity.sol";
import {UNIVERSAL_DELEGATOR_VERSION} from "../../../src/interfaces/delegator/IUniversalDelegator.sol";

contract DeployV2BaseScript is Script {
    struct DeployParams {
        address adapterRegistryOwner;
        address protocolFeeRegistryOwner;
        address adapterFactoryOwner;
        address morphoVaultFactory;
        address morphoAdapterRegistry;
        address aavePool;
        address cowSwapSettlement;
        address merklDistributor;
        address networkMiddlewareService;
    }

    struct DeploymentData {
        SymbioticCoreConstants.Core core;
        AdapterRegistry adapterRegistry;
        ProtocolFeeRegistry protocolFeeRegistry;
        WithdrawalQueueFactory withdrawalQueueFactory;
        WithdrawalQueue withdrawalQueue;
        UniversalDelegatorFactory universalDelegatorFactory;
        VaultV2 vaultV2;
        UniversalDelegator universalDelegator;
        AdapterFactory morphoVaultV2AdapterFactory;
        MorphoVaultV2Adapter morphoVaultV2Adapter;
        AdapterFactory aaveV3AdapterFactory;
        AaveV3Adapter aaveV3Adapter;
        AdapterFactory appAdapterFactory;
        AppAdapter appAdapter;
        AdapterFactory restakingAppAdapterFactory;
        RestakingAppAdapter restakingAppAdapter;
    }

    function runBase(address owner) public virtual returns (DeploymentData memory data) {
        data = runBase(owner, owner, owner);
    }

    function runBase(address adapterRegistryOwner, address protocolFeeRegistryOwner)
        public
        virtual
        returns (DeploymentData memory data)
    {
        data = runBase(adapterRegistryOwner, protocolFeeRegistryOwner, adapterRegistryOwner);
    }

    function runBase(address adapterRegistryOwner, address protocolFeeRegistryOwner, address adapterFactoryOwner)
        public
        virtual
        returns (DeploymentData memory data)
    {
        require(adapterRegistryOwner != address(0), "invalid adapter registry owner");
        require(protocolFeeRegistryOwner != address(0), "invalid protocol fee registry owner");
        require(adapterFactoryOwner != address(0), "invalid adapter factory owner");

        data.core = _core();

        _startBroadcast();
        address broadcaster = _scriptOwner();
        data.adapterRegistry = new AdapterRegistry(adapterRegistryOwner);
        data.protocolFeeRegistry = new ProtocolFeeRegistry(protocolFeeRegistryOwner);
        data.withdrawalQueueFactory = new WithdrawalQueueFactory(broadcaster);
        data.withdrawalQueue = new WithdrawalQueue(address(data.withdrawalQueueFactory));
        data.withdrawalQueueFactory.whitelist(address(data.withdrawalQueue));
        if (adapterFactoryOwner != broadcaster) {
            data.withdrawalQueueFactory.transferOwnership(adapterFactoryOwner);
        }
        data.universalDelegatorFactory = new UniversalDelegatorFactory(broadcaster);
        data.vaultV2 = new VaultV2(
            address(data.core.vaultFactory),
            address(data.universalDelegatorFactory),
            address(data.protocolFeeRegistry),
            address(data.withdrawalQueueFactory)
        );
        data.universalDelegator =
            new UniversalDelegator(address(data.adapterRegistry), address(data.universalDelegatorFactory));
        data.universalDelegatorFactory.whitelist(address(data.universalDelegator));
        if (adapterFactoryOwner != broadcaster) {
            data.universalDelegatorFactory.transferOwnership(adapterFactoryOwner);
        }
        _stopBroadcast();

        assert(data.adapterRegistry.owner() == adapterRegistryOwner);
        assert(data.protocolFeeRegistry.owner() == protocolFeeRegistryOwner);
        assert(data.withdrawalQueueFactory.owner() == adapterFactoryOwner);
        assert(data.universalDelegatorFactory.owner() == adapterFactoryOwner);
        assert(IMigratableEntity(address(data.vaultV2)).FACTORY() == address(data.core.vaultFactory));
        assert(IMigratableEntity(address(data.universalDelegator)).FACTORY() == address(data.universalDelegatorFactory));
        assert(
            data.universalDelegatorFactory.implementation(UNIVERSAL_DELEGATOR_VERSION)
                == address(data.universalDelegator)
        );

        Logs.log(string.concat("Deployed AdapterRegistry: ", vm.toString(address(data.adapterRegistry))));
        Logs.log(string.concat("Deployed ProtocolFeeRegistry: ", vm.toString(address(data.protocolFeeRegistry))));
        Logs.log(string.concat("Deployed WithdrawalQueueFactory: ", vm.toString(address(data.withdrawalQueueFactory))));
        Logs.log(string.concat("Deployed WithdrawalQueue: ", vm.toString(address(data.withdrawalQueue))));
        Logs.log(
            string.concat("Deployed UniversalDelegatorFactory: ", vm.toString(address(data.universalDelegatorFactory)))
        );
        Logs.log(string.concat("Deployed VaultV2: ", vm.toString(address(data.vaultV2))));
        Logs.log(string.concat("Deployed UniversalDelegator: ", vm.toString(address(data.universalDelegator))));
    }

    function runBase(DeployParams memory params) public virtual returns (DeploymentData memory data) {
        _validateParams(params);

        data = runBase(params.adapterRegistryOwner, params.protocolFeeRegistryOwner, params.adapterFactoryOwner);

        _startBroadcast();
        _deployAdapterFactories(data, params);
        _stopBroadcast();

        _validateAdapterDeployment(
            data.morphoVaultV2AdapterFactory, address(data.morphoVaultV2Adapter), params.adapterFactoryOwner
        );
        _validateAdapterDeployment(data.aaveV3AdapterFactory, address(data.aaveV3Adapter), params.adapterFactoryOwner);
        _validateAdapterDeployment(data.appAdapterFactory, address(data.appAdapter), params.adapterFactoryOwner);
        _validateAdapterDeployment(
            data.restakingAppAdapterFactory, address(data.restakingAppAdapter), params.adapterFactoryOwner
        );

        Logs.log(
            string.concat(
                "Deployed V2 adapter factories",
                "\n    morphoVaultV2AdapterFactory:",
                vm.toString(address(data.morphoVaultV2AdapterFactory)),
                "\n    morphoVaultV2Adapter:",
                vm.toString(address(data.morphoVaultV2Adapter)),
                "\n    aaveV3AdapterFactory:",
                vm.toString(address(data.aaveV3AdapterFactory)),
                "\n    aaveV3Adapter:",
                vm.toString(address(data.aaveV3Adapter)),
                "\n    appAdapterFactory:",
                vm.toString(address(data.appAdapterFactory)),
                "\n    appAdapter:",
                vm.toString(address(data.appAdapter)),
                "\n    restakingAppAdapterFactory:",
                vm.toString(address(data.restakingAppAdapterFactory)),
                "\n    restakingAppAdapter:",
                vm.toString(address(data.restakingAppAdapter))
            )
        );
    }

    function _startBroadcast() internal virtual {
        vm.startBroadcast();
    }

    function _stopBroadcast() internal virtual {
        vm.stopBroadcast();
    }

    function _scriptOwner() internal view virtual returns (address owner_) {
        (,, address origin) = vm.readCallers();
        return origin == address(0) ? msg.sender : origin;
    }

    function _core() internal view virtual returns (SymbioticCoreConstants.Core memory) {
        return SymbioticCoreConstants.core();
    }

    function _deployAdapterFactories(DeploymentData memory data, DeployParams memory params) internal {
        address broadcaster = _scriptOwner();
        address vaultFactory = address(data.core.vaultFactory);

        data.morphoVaultV2AdapterFactory = new AdapterFactory(broadcaster);
        data.morphoVaultV2Adapter = new MorphoVaultV2Adapter(
            vaultFactory,
            address(data.morphoVaultV2AdapterFactory),
            params.merklDistributor,
            params.cowSwapSettlement,
            params.morphoVaultFactory,
            params.morphoAdapterRegistry
        );
        data.morphoVaultV2AdapterFactory.whitelist(address(data.morphoVaultV2Adapter));

        data.aaveV3AdapterFactory = new AdapterFactory(broadcaster);
        data.aaveV3Adapter = new AaveV3Adapter(
            params.aavePool,
            vaultFactory,
            address(data.aaveV3AdapterFactory),
            params.merklDistributor,
            params.cowSwapSettlement
        );
        data.aaveV3AdapterFactory.whitelist(address(data.aaveV3Adapter));

        data.appAdapterFactory = new AdapterFactory(broadcaster);
        data.appAdapter = new AppAdapter(
            vaultFactory, address(data.appAdapterFactory), params.cowSwapSettlement, params.networkMiddlewareService
        );
        data.appAdapterFactory.whitelist(address(data.appAdapter));

        data.restakingAppAdapterFactory = new AdapterFactory(broadcaster);
        data.restakingAppAdapter = new RestakingAppAdapter(
            vaultFactory,
            address(data.restakingAppAdapterFactory),
            params.cowSwapSettlement,
            params.networkMiddlewareService
        );
        data.restakingAppAdapterFactory.whitelist(address(data.restakingAppAdapter));

        if (params.adapterFactoryOwner != broadcaster) {
            data.morphoVaultV2AdapterFactory.transferOwnership(params.adapterFactoryOwner);
            data.aaveV3AdapterFactory.transferOwnership(params.adapterFactoryOwner);
            data.appAdapterFactory.transferOwnership(params.adapterFactoryOwner);
            data.restakingAppAdapterFactory.transferOwnership(params.adapterFactoryOwner);
        }
    }

    function _validateAdapterDeployment(AdapterFactory adapterFactory, address adapterImplementation, address owner)
        internal
        view
    {
        assert(adapterFactory.owner() == owner);
        assert(IMigratableEntity(adapterImplementation).FACTORY() == address(adapterFactory));
        assert(adapterFactory.implementation(1) == adapterImplementation);
    }

    function _validateParams(DeployParams memory params) internal pure {
        require(params.adapterRegistryOwner != address(0), "invalid adapter registry owner");
        require(params.protocolFeeRegistryOwner != address(0), "invalid protocol fee registry owner");
        require(params.adapterFactoryOwner != address(0), "invalid adapter factory owner");
        require(params.morphoVaultFactory != address(0), "invalid Morpho vault factory");
        require(params.morphoAdapterRegistry != address(0), "invalid Morpho adapter registry");
        require(params.aavePool != address(0), "invalid Aave pool");
        require(params.cowSwapSettlement != address(0), "invalid CoW settlement");
        require(params.merklDistributor != address(0), "invalid Merkl distributor");
        require(params.networkMiddlewareService != address(0), "invalid network middleware service");
    }
}
