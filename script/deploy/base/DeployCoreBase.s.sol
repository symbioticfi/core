// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {Logs} from "../../utils/Logs.sol";

import {VaultFactory} from "../../../src/contracts/VaultFactory.sol";
import {DelegatorFactory} from "../../../src/contracts/DelegatorFactory.sol";
import {SlasherFactory} from "../../../src/contracts/SlasherFactory.sol";
import {NetworkRegistry} from "../../../src/contracts/NetworkRegistry.sol";
import {OperatorRegistry} from "../../../src/contracts/OperatorRegistry.sol";
import {MetadataService} from "../../../src/contracts/service/MetadataService.sol";
import {NetworkMiddlewareService} from "../../../src/contracts/service/NetworkMiddlewareService.sol";
import {OptInService} from "../../../src/contracts/service/OptInService.sol";

import {Vault} from "../../../src/contracts/vault/Vault.sol";
import {VaultTokenized} from "../../../src/contracts/vault/VaultTokenized.sol";
import {NetworkRestakeDelegator} from "../../../src/contracts/delegator/NetworkRestakeDelegator.sol";
import {FullRestakeDelegator} from "../../../src/contracts/delegator/FullRestakeDelegator.sol";
import {OperatorSpecificDelegator} from "../../../src/contracts/delegator/OperatorSpecificDelegator.sol";
import {OperatorNetworkSpecificDelegator} from "../../../src/contracts/delegator/OperatorNetworkSpecificDelegator.sol";
import {Slasher} from "../../../src/contracts/slasher/Slasher.sol";
import {VetoSlasher} from "../../../src/contracts/slasher/VetoSlasher.sol";

import {VaultConfigurator} from "../../../src/contracts/VaultConfigurator.sol";

contract DeployCoreBaseScript is Script {
    struct DeploymentData {
        VaultFactory vaultFactory;
        DelegatorFactory delegatorFactory;
        SlasherFactory slasherFactory;
        NetworkRegistry networkRegistry;
        OperatorRegistry operatorRegistry;
        MetadataService operatorMetadataService;
        MetadataService networkMetadataService;
        NetworkMiddlewareService networkMiddlewareService;
        OptInService operatorVaultOptInService;
        OptInService operatorNetworkOptInService;
        address vaultImpl;
        address vaultTokenizedImpl;
        address networkRestakeDelegatorImpl;
        address fullRestakeDelegatorImpl;
        address operatorSpecificDelegatorImpl;
        address operatorNetworkSpecificDelegatorImpl;
        address slasherImpl;
        address vetoSlasherImpl;
        VaultConfigurator vaultConfigurator;
    }

    function run(address owner) public {
        vm.startBroadcast();
        (,, address deployer) = vm.readCallers();

        DeploymentData memory data;

        data.vaultFactory = new VaultFactory(deployer);
        data.delegatorFactory = new DelegatorFactory(deployer);
        data.slasherFactory = new SlasherFactory(deployer);
        data.networkRegistry = new NetworkRegistry();
        data.operatorRegistry = new OperatorRegistry();
        data.operatorMetadataService = new MetadataService(address(data.operatorRegistry));
        data.networkMetadataService = new MetadataService(address(data.networkRegistry));
        data.networkMiddlewareService = new NetworkMiddlewareService(address(data.networkRegistry));
        data.operatorVaultOptInService =
            new OptInService(address(data.operatorRegistry), address(data.vaultFactory), "OperatorVaultOptInService");
        data.operatorNetworkOptInService = new OptInService(
            address(data.operatorRegistry), address(data.networkRegistry), "OperatorNetworkOptInService"
        );

        data.vaultImpl = address(
            new Vault(address(data.delegatorFactory), address(data.slasherFactory), address(data.vaultFactory))
        );
        data.vaultFactory.whitelist(data.vaultImpl);
        assert(data.vaultFactory.implementation(1) == address(data.vaultImpl));
        data.vaultTokenizedImpl = address(
            new VaultTokenized(address(data.delegatorFactory), address(data.slasherFactory), address(data.vaultFactory))
        );
        data.vaultFactory.whitelist(data.vaultTokenizedImpl);
        assert(data.vaultFactory.implementation(2) == address(data.vaultTokenizedImpl));

        data.networkRestakeDelegatorImpl = address(
            new NetworkRestakeDelegator(
                address(data.networkRegistry),
                address(data.vaultFactory),
                address(data.operatorVaultOptInService),
                address(data.operatorNetworkOptInService),
                address(data.delegatorFactory),
                data.delegatorFactory.totalTypes()
            )
        );
        data.delegatorFactory.whitelist(data.networkRestakeDelegatorImpl);
        assert(NetworkRestakeDelegator(data.networkRestakeDelegatorImpl).TYPE() == 0);

        data.fullRestakeDelegatorImpl = address(
            new FullRestakeDelegator(
                address(data.networkRegistry),
                address(data.vaultFactory),
                address(data.operatorVaultOptInService),
                address(data.operatorNetworkOptInService),
                address(data.delegatorFactory),
                data.delegatorFactory.totalTypes()
            )
        );
        data.delegatorFactory.whitelist(data.fullRestakeDelegatorImpl);
        assert(FullRestakeDelegator(data.fullRestakeDelegatorImpl).TYPE() == 1);

        data.operatorSpecificDelegatorImpl = address(
            new OperatorSpecificDelegator(
                address(data.operatorRegistry),
                address(data.networkRegistry),
                address(data.vaultFactory),
                address(data.operatorVaultOptInService),
                address(data.operatorNetworkOptInService),
                address(data.delegatorFactory),
                data.delegatorFactory.totalTypes()
            )
        );
        data.delegatorFactory.whitelist(data.operatorSpecificDelegatorImpl);
        assert(OperatorSpecificDelegator(data.operatorSpecificDelegatorImpl).TYPE() == 2);

        data.operatorNetworkSpecificDelegatorImpl = address(
            new OperatorNetworkSpecificDelegator(
                address(data.operatorRegistry),
                address(data.networkRegistry),
                address(data.vaultFactory),
                address(data.operatorVaultOptInService),
                address(data.operatorNetworkOptInService),
                address(data.delegatorFactory),
                data.delegatorFactory.totalTypes()
            )
        );
        data.delegatorFactory.whitelist(data.operatorNetworkSpecificDelegatorImpl);
        assert(OperatorNetworkSpecificDelegator(data.operatorNetworkSpecificDelegatorImpl).TYPE() == 3);

        data.slasherImpl = address(
            new Slasher(
                address(data.vaultFactory),
                address(data.networkMiddlewareService),
                address(data.slasherFactory),
                data.slasherFactory.totalTypes()
            )
        );
        data.slasherFactory.whitelist(data.slasherImpl);
        assert(Slasher(data.slasherImpl).TYPE() == 0);

        data.vetoSlasherImpl = address(
            new VetoSlasher(
                address(data.vaultFactory),
                address(data.networkMiddlewareService),
                address(data.networkRegistry),
                address(data.slasherFactory),
                data.slasherFactory.totalTypes()
            )
        );
        data.slasherFactory.whitelist(data.vetoSlasherImpl);
        assert(VetoSlasher(data.vetoSlasherImpl).TYPE() == 1);

        data.vaultConfigurator = new VaultConfigurator(
            address(data.vaultFactory), address(data.delegatorFactory), address(data.slasherFactory)
        );

        data.vaultFactory.transferOwnership(owner);
        data.delegatorFactory.transferOwnership(owner);
        data.slasherFactory.transferOwnership(owner);
        assert(data.vaultFactory.owner() == owner);
        assert(data.delegatorFactory.owner() == owner);
        assert(data.slasherFactory.owner() == owner);
        vm.stopBroadcast();

        Logs.log(string.concat("Deployed VaultFactory: ", vm.toString(address(data.vaultFactory))));
        Logs.log(string.concat("Deployed DelegatorFactory: ", vm.toString(address(data.delegatorFactory))));
        Logs.log(string.concat("Deployed SlasherFactory: ", vm.toString(address(data.slasherFactory))));
        Logs.log(string.concat("Deployed NetworkRegistry: ", vm.toString(address(data.networkRegistry))));
        Logs.log(string.concat("Deployed OperatorRegistry: ", vm.toString(address(data.operatorRegistry))));
        Logs.log(
            string.concat("Deployed OperatorMetadataService: ", vm.toString(address(data.operatorMetadataService)))
        );
        Logs.log(string.concat("Deployed NetworkMetadataService: ", vm.toString(address(data.networkMetadataService))));
        Logs.log(
            string.concat("Deployed NetworkMiddlewareService: ", vm.toString(address(data.networkMiddlewareService)))
        );
        Logs.log(
            string.concat("Deployed OperatorVaultOptInService: ", vm.toString(address(data.operatorVaultOptInService)))
        );
        Logs.log(
            string.concat(
                "Deployed OperatorNetworkOptInService: ", vm.toString(address(data.operatorNetworkOptInService))
            )
        );
        Logs.log(string.concat("Deployed VaultConfigurator: ", vm.toString(address(data.vaultConfigurator))));
    }
}
