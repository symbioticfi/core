// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {Logs} from "../../utils/Logs.sol";
import {SymbioticCoreConstants} from "../../../test/integration/SymbioticCoreConstants.sol";

import {AdapterRegistry} from "../../../src/contracts/AdapterRegistry.sol";
import {UniversalDelegator} from "../../../src/contracts/delegator/UniversalDelegator.sol";
import {UniversalSlasher} from "../../../src/contracts/slasher/UniversalSlasher.sol";
import {VaultV2} from "../../../src/contracts/vault/VaultV2.sol";
import {VaultV2Migrate} from "../../../src/contracts/vault/VaultV2Migrate.sol";

import {IEntity} from "../../../src/interfaces/common/IEntity.sol";
import {IMigratableEntity} from "../../../src/interfaces/common/IMigratableEntity.sol";
import {UNIVERSAL_DELEGATOR_TYPE} from "../../../src/interfaces/delegator/IUniversalDelegator.sol";
import {UNIVERSAL_SLASHER_TYPE} from "../../../src/interfaces/slasher/IUniversalSlasher.sol";

contract V2DeployBaseScript is Script {
    struct DeploymentData {
        SymbioticCoreConstants.Core core;
        AdapterRegistry adapterRegistry;
        VaultV2Migrate vaultV2Migrate;
        VaultV2 vaultV2;
        UniversalDelegator universalDelegator;
        UniversalSlasher universalSlasher;
    }

    function runBase(address adapterRegistryOwner, address feeRegistry, address rewards)
        public
        virtual
        returns (DeploymentData memory data)
    {
        require(adapterRegistryOwner != address(0), "invalid adapter registry owner");

        data.core = SymbioticCoreConstants.core();

        _startBroadcast();
        data.adapterRegistry = new AdapterRegistry(adapterRegistryOwner);
        data.vaultV2Migrate = new VaultV2Migrate(
            address(data.core.delegatorFactory),
            address(data.core.slasherFactory),
            feeRegistry,
            rewards,
            address(data.adapterRegistry)
        );
        data.vaultV2 = new VaultV2(
            address(data.core.delegatorFactory),
            address(data.core.slasherFactory),
            address(data.core.vaultFactory),
            feeRegistry,
            rewards,
            address(data.adapterRegistry),
            address(data.vaultV2Migrate)
        );
        data.universalDelegator = new UniversalDelegator(
            address(data.core.networkRegistry),
            address(data.core.vaultFactory),
            address(data.core.delegatorFactory),
            data.core.delegatorFactory.totalTypes(),
            address(data.core.networkMiddlewareService)
        );
        data.universalSlasher = new UniversalSlasher(
            address(data.core.vaultFactory),
            address(data.core.networkMiddlewareService),
            address(data.core.networkRegistry),
            address(data.core.slasherFactory),
            data.core.slasherFactory.totalTypes()
        );
        _stopBroadcast();

        assert(Ownable(address(data.adapterRegistry)).owner() == adapterRegistryOwner);
        assert(IMigratableEntity(address(data.vaultV2)).FACTORY() == address(data.core.vaultFactory));
        assert(IEntity(address(data.universalDelegator)).TYPE() == UNIVERSAL_DELEGATOR_TYPE);
        assert(IEntity(address(data.universalSlasher)).TYPE() == UNIVERSAL_SLASHER_TYPE);

        Logs.log(string.concat("Deployed AdapterRegistry: ", vm.toString(address(data.adapterRegistry))));
        Logs.log(string.concat("Deployed VaultV2Migrate: ", vm.toString(address(data.vaultV2Migrate))));
        Logs.log(string.concat("Deployed VaultV2: ", vm.toString(address(data.vaultV2))));
        Logs.log(string.concat("Deployed UniversalDelegator: ", vm.toString(address(data.universalDelegator))));
        Logs.log(string.concat("Deployed UniversalSlasher: ", vm.toString(address(data.universalSlasher))));
    }

    function _startBroadcast() internal virtual {
        vm.startBroadcast();
    }

    function _stopBroadcast() internal virtual {
        vm.stopBroadcast();
    }
}
