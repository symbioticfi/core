// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {Script, console2} from "forge-std/Script.sol";

import {VaultFactory} from "src/contracts/VaultFactory.sol";
import {DelegatorFactory} from "src/contracts/DelegatorFactory.sol";
import {SlasherFactory} from "src/contracts/SlasherFactory.sol";
import {NetworkRegistry} from "src/contracts/NetworkRegistry.sol";
import {OperatorRegistry} from "src/contracts/OperatorRegistry.sol";
import {MetadataService} from "src/contracts/service/MetadataService.sol";
import {NetworkMiddlewareService} from "src/contracts/service/NetworkMiddlewareService.sol";
import {OptInService} from "src/contracts/service/OptInService.sol";

import {Vault} from "src/contracts/vault/Vault.sol";
import {NetworkRestakeDelegator} from "src/contracts/delegator/NetworkRestakeDelegator.sol";
import {FullRestakeDelegator} from "src/contracts/delegator/FullRestakeDelegator.sol";
import {Slasher} from "src/contracts/slasher/Slasher.sol";
import {VetoSlasher} from "src/contracts/slasher/VetoSlasher.sol";

import {VaultConfigurator} from "src/contracts/VaultConfigurator.sol";

contract CoreScript is Script {
    function run(address owner) public {
        vm.startBroadcast();
        (,, address deployer) = vm.readCallers();

        VaultFactory vaultFactory = new VaultFactory(deployer);
        DelegatorFactory delegatorFactory = new DelegatorFactory(deployer);
        SlasherFactory slasherFactory = new SlasherFactory(deployer);
        NetworkRegistry networkRegistry = new NetworkRegistry();
        OperatorRegistry operatorRegistry = new OperatorRegistry();
        MetadataService operatorMetadataService = new MetadataService(address(operatorRegistry));
        MetadataService networkMetadataService = new MetadataService(address(networkRegistry));
        NetworkMiddlewareService networkMiddlewareService = new NetworkMiddlewareService(address(networkRegistry));
        OptInService networkVaultOptInService = new OptInService(address(networkRegistry), address(vaultFactory));
        OptInService operatorVaultOptInService = new OptInService(address(operatorRegistry), address(vaultFactory));
        OptInService operatorNetworkOptInService = new OptInService(address(operatorRegistry), address(networkRegistry));

        address vaultImpl =
            address(new Vault(address(delegatorFactory), address(slasherFactory), address(vaultFactory)));
        vaultFactory.whitelist(vaultImpl);

        address networkRestakeDelegatorImpl = address(
            new NetworkRestakeDelegator(
                address(networkRegistry),
                address(vaultFactory),
                address(operatorVaultOptInService),
                address(operatorNetworkOptInService),
                address(delegatorFactory),
                delegatorFactory.totalTypes()
            )
        );
        delegatorFactory.whitelist(networkRestakeDelegatorImpl);

        address fullRestakeDelegatorImpl = address(
            new FullRestakeDelegator(
                address(networkRegistry),
                address(vaultFactory),
                address(operatorVaultOptInService),
                address(operatorNetworkOptInService),
                address(delegatorFactory),
                delegatorFactory.totalTypes()
            )
        );
        delegatorFactory.whitelist(fullRestakeDelegatorImpl);

        address slasherImpl = address(
            new Slasher(
                address(vaultFactory),
                address(networkMiddlewareService),
                address(networkVaultOptInService),
                address(operatorVaultOptInService),
                address(operatorNetworkOptInService),
                address(slasherFactory),
                slasherFactory.totalTypes()
            )
        );
        slasherFactory.whitelist(slasherImpl);

        address vetoSlasherImpl = address(
            new VetoSlasher(
                address(vaultFactory),
                address(networkMiddlewareService),
                address(networkVaultOptInService),
                address(operatorVaultOptInService),
                address(operatorNetworkOptInService),
                address(networkRegistry),
                address(slasherFactory),
                slasherFactory.totalTypes()
            )
        );
        slasherFactory.whitelist(vetoSlasherImpl);

        VaultConfigurator vaultConfigurator =
            new VaultConfigurator(address(vaultFactory), address(delegatorFactory), address(slasherFactory));

        vaultFactory.transferOwnership(owner);
        delegatorFactory.transferOwnership(owner);
        slasherFactory.transferOwnership(owner);

        console2.log("VaultFactory: ", address(vaultFactory));
        console2.log("DelegatorFactory: ", address(delegatorFactory));
        console2.log("SlasherFactory: ", address(slasherFactory));
        console2.log("NetworkRegistry: ", address(networkRegistry));
        console2.log("OperatorRegistry: ", address(operatorRegistry));
        console2.log("OperatorMetadataService: ", address(operatorMetadataService));
        console2.log("NetworkMetadataService: ", address(networkMetadataService));
        console2.log("NetworkMiddlewareService: ", address(networkMiddlewareService));
        console2.log("NetworkVaultOptInService: ", address(networkVaultOptInService));
        console2.log("OperatorVaultOptInService: ", address(operatorVaultOptInService));
        console2.log("OperatorNetworkOptInService: ", address(operatorNetworkOptInService));
        console2.log("VaultConfigurator: ", address(vaultConfigurator));

        vm.stopBroadcast();
    }
}
