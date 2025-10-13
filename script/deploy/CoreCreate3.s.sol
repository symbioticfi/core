// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {Script, console2} from "forge-std/Script.sol";

import {CreateXWrapper} from "../utils/CreateXWrapper.sol";
import {VaultFactory} from "../../src/contracts/VaultFactory.sol";
import {DelegatorFactory} from "../../src/contracts/DelegatorFactory.sol";
import {SlasherFactory} from "../../src/contracts/SlasherFactory.sol";
import {NetworkRegistry} from "../../src/contracts/NetworkRegistry.sol";
import {OperatorRegistry} from "../../src/contracts/OperatorRegistry.sol";
import {MetadataService} from "../../src/contracts/service/MetadataService.sol";
import {NetworkMiddlewareService} from "../../src/contracts/service/NetworkMiddlewareService.sol";
import {OptInService} from "../../src/contracts/service/OptInService.sol";
import {VaultConfigurator} from "../../src/contracts/VaultConfigurator.sol";
import {Vault} from "../../src/contracts/vault/Vault.sol";
import {VaultTokenized} from "../../src/contracts/vault/VaultTokenized.sol";
import {NetworkRestakeDelegator} from "../../src/contracts/delegator/NetworkRestakeDelegator.sol";
import {FullRestakeDelegator} from "../../src/contracts/delegator/FullRestakeDelegator.sol";
import {OperatorSpecificDelegator} from "../../src/contracts/delegator/OperatorSpecificDelegator.sol";
import {OperatorNetworkSpecificDelegator} from "../../src/contracts/delegator/OperatorNetworkSpecificDelegator.sol";
import {Slasher} from "../../src/contracts/slasher/Slasher.sol";
import {VetoSlasher} from "../../src/contracts/slasher/VetoSlasher.sol";
/**
 * @title CoreCreate3Script
 * @notice Deployment script for Symbiotic Core contracts using CREATE3
 * @dev This script deploys core infrastructure contracts using CREATE3 via CreateXWrapper for deterministic addresses
 */

contract CoreCreate3Script is Script, CreateXWrapper {
    /// @notice CREATE3 salts for contract deployments
    bytes11 public constant VAULT_FACTORY_SALT = bytes11("VaultFac");
    bytes11 public constant DELEGATOR_FACTORY_SALT = bytes11("DelFac");
    bytes11 public constant SLASHER_FACTORY_SALT = bytes11("SlashFac");
    bytes11 public constant NETWORK_REGISTRY_SALT = bytes11("NetReg");
    bytes11 public constant OPERATOR_REGISTRY_SALT = bytes11("OpReg");
    bytes11 public constant OPERATOR_METADATA_SERVICE_SALT = bytes11("OpMeta");
    bytes11 public constant NETWORK_METADATA_SERVICE_SALT = bytes11("NetMeta");
    bytes11 public constant NETWORK_MIDDLEWARE_SERVICE_SALT = bytes11("NetMid");
    bytes11 public constant OPERATOR_VAULT_OPTIN_SERVICE_SALT = bytes11("OpVaultOpt");
    bytes11 public constant OPERATOR_NETWORK_OPTIN_SERVICE_SALT = bytes11("OpNetOpt");
    bytes11 public constant VAULT_CONFIGURATOR_SALT = bytes11("VaultConf");

    /**
     * @notice Main deployment function using CREATE3
     * @param owner The owner address for the factory contracts
     */
    function run(
        address owner
    ) public {
        vm.startBroadcast();
        (,, address deployer) = vm.readCallers();

        console2.log("Deploying Core contracts with CREATE3...");
        console2.log("Deployer:", deployer);
        console2.log("Owner:", owner);
        console2.log("");

        // Deploy factories
        VaultFactory vaultFactory =
            VaultFactory(_deployContract(VAULT_FACTORY_SALT, type(VaultFactory).creationCode, abi.encode(deployer)));
        console2.log("VaultFactory: ", address(vaultFactory));

        DelegatorFactory delegatorFactory = DelegatorFactory(
            _deployContract(DELEGATOR_FACTORY_SALT, type(DelegatorFactory).creationCode, abi.encode(deployer))
        );
        console2.log("DelegatorFactory: ", address(delegatorFactory));

        SlasherFactory slasherFactory = SlasherFactory(
            _deployContract(SLASHER_FACTORY_SALT, type(SlasherFactory).creationCode, abi.encode(deployer))
        );
        console2.log("SlasherFactory: ", address(slasherFactory));

        // Deploy registries
        NetworkRegistry networkRegistry =
            NetworkRegistry(_deployContract(NETWORK_REGISTRY_SALT, type(NetworkRegistry).creationCode, ""));
        console2.log("NetworkRegistry: ", address(networkRegistry));

        OperatorRegistry operatorRegistry =
            OperatorRegistry(_deployContract(OPERATOR_REGISTRY_SALT, type(OperatorRegistry).creationCode, ""));
        console2.log("OperatorRegistry: ", address(operatorRegistry));

        // Deploy services
        MetadataService operatorMetadataService = MetadataService(
            _deployContract(
                OPERATOR_METADATA_SERVICE_SALT,
                type(MetadataService).creationCode,
                abi.encode(address(operatorRegistry))
            )
        );
        console2.log("OperatorMetadataService: ", address(operatorMetadataService));

        MetadataService networkMetadataService = MetadataService(
            _deployContract(
                NETWORK_METADATA_SERVICE_SALT, type(MetadataService).creationCode, abi.encode(address(networkRegistry))
            )
        );
        console2.log("NetworkMetadataService: ", address(networkMetadataService));

        NetworkMiddlewareService networkMiddlewareService = NetworkMiddlewareService(
            _deployContract(
                NETWORK_MIDDLEWARE_SERVICE_SALT,
                type(NetworkMiddlewareService).creationCode,
                abi.encode(address(networkRegistry))
            )
        );
        console2.log("NetworkMiddlewareService: ", address(networkMiddlewareService));

        OptInService operatorVaultOptInService = OptInService(
            _deployContract(
                OPERATOR_VAULT_OPTIN_SERVICE_SALT,
                type(OptInService).creationCode,
                abi.encode(address(operatorRegistry), address(vaultFactory), "OperatorVaultOptInService")
            )
        );
        console2.log("OperatorVaultOptInService: ", address(operatorVaultOptInService));

        OptInService operatorNetworkOptInService = OptInService(
            _deployContract(
                OPERATOR_NETWORK_OPTIN_SERVICE_SALT,
                type(OptInService).creationCode,
                abi.encode(address(operatorRegistry), address(networkRegistry), "OperatorNetworkOptInService")
            )
        );
        console2.log("OperatorNetworkOptInService: ", address(operatorNetworkOptInService));

        // Deploy VaultConfigurator
        VaultConfigurator vaultConfigurator = VaultConfigurator(
            _deployContract(
                VAULT_CONFIGURATOR_SALT,
                type(VaultConfigurator).creationCode,
                abi.encode(address(vaultFactory), address(delegatorFactory), address(slasherFactory))
            )
        );
        console2.log("VaultConfigurator: ", address(vaultConfigurator));

        console2.log("");
        console2.log("Deploying and whitelisting implementations...");

        // Deploy and whitelist Vault implementations
        address vaultImpl =
            address(new Vault(address(delegatorFactory), address(slasherFactory), address(vaultFactory)));
        vaultFactory.whitelist(vaultImpl);
        assert(vaultFactory.implementation(1) == address(vaultImpl));
        console2.log("Vault implementation: ", vaultImpl);

        address vaultTokenizedImpl =
            address(new VaultTokenized(address(delegatorFactory), address(slasherFactory), address(vaultFactory)));
        vaultFactory.whitelist(vaultTokenizedImpl);
        assert(vaultFactory.implementation(2) == address(vaultTokenizedImpl));
        console2.log("VaultTokenized implementation: ", vaultTokenizedImpl);

        // Deploy and whitelist Delegator implementations
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
        assert(NetworkRestakeDelegator(networkRestakeDelegatorImpl).TYPE() == 0);
        console2.log("NetworkRestakeDelegator implementation: ", networkRestakeDelegatorImpl);

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
        assert(FullRestakeDelegator(fullRestakeDelegatorImpl).TYPE() == 1);
        console2.log("FullRestakeDelegator implementation: ", fullRestakeDelegatorImpl);

        address operatorSpecificDelegatorImpl = address(
            new OperatorSpecificDelegator(
                address(operatorRegistry),
                address(networkRegistry),
                address(vaultFactory),
                address(operatorVaultOptInService),
                address(operatorNetworkOptInService),
                address(delegatorFactory),
                delegatorFactory.totalTypes()
            )
        );
        delegatorFactory.whitelist(operatorSpecificDelegatorImpl);
        assert(OperatorSpecificDelegator(operatorSpecificDelegatorImpl).TYPE() == 2);
        console2.log("OperatorSpecificDelegator implementation: ", operatorSpecificDelegatorImpl);

        address operatorNetworkSpecificDelegatorImpl = address(
            new OperatorNetworkSpecificDelegator(
                address(operatorRegistry),
                address(networkRegistry),
                address(vaultFactory),
                address(operatorVaultOptInService),
                address(operatorNetworkOptInService),
                address(delegatorFactory),
                delegatorFactory.totalTypes()
            )
        );
        delegatorFactory.whitelist(operatorNetworkSpecificDelegatorImpl);
        assert(OperatorNetworkSpecificDelegator(operatorNetworkSpecificDelegatorImpl).TYPE() == 3);
        console2.log("OperatorNetworkSpecificDelegator implementation: ", operatorNetworkSpecificDelegatorImpl);

        // Deploy and whitelist Slasher implementations
        address slasherImpl = address(
            new Slasher(
                address(vaultFactory),
                address(networkMiddlewareService),
                address(slasherFactory),
                slasherFactory.totalTypes()
            )
        );
        slasherFactory.whitelist(slasherImpl);
        assert(Slasher(slasherImpl).TYPE() == 0);
        console2.log("Slasher implementation: ", slasherImpl);

        address vetoSlasherImpl = address(
            new VetoSlasher(
                address(vaultFactory),
                address(networkMiddlewareService),
                address(networkRegistry),
                address(slasherFactory),
                slasherFactory.totalTypes()
            )
        );
        slasherFactory.whitelist(vetoSlasherImpl);
        assert(VetoSlasher(vetoSlasherImpl).TYPE() == 1);
        console2.log("VetoSlasher implementation: ", vetoSlasherImpl);

        // Transfer ownership to the specified owner
        vaultFactory.transferOwnership(owner);
        delegatorFactory.transferOwnership(owner);
        slasherFactory.transferOwnership(owner);
        assert(vaultFactory.owner() == owner);
        assert(delegatorFactory.owner() == owner);
        assert(slasherFactory.owner() == owner);

        console2.log("");
        console2.log("Deployment complete! All factories ownership transferred to:", owner);

        vm.stopBroadcast();
    }

    /**
     * @notice Internal function to deploy a contract using CREATE3
     * @dev Deploys using CREATE3 with a simple salt (no deployer guard)
     * @param salt The CREATE3 salt for deterministic deployment
     * @param creationCode The contract creation bytecode
     * @param constructorArgs The ABI-encoded constructor arguments
     * @return newContract The address of the deployed contract
     */
    function _deployContract(
        bytes11 salt,
        bytes memory creationCode,
        bytes memory constructorArgs
    ) internal returns (address newContract) {
        bytes memory initCode = abi.encodePacked(creationCode, constructorArgs);
        newContract = deployCreate3(bytes32(salt), initCode);
    }
}
