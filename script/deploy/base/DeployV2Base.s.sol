// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {Logs} from "../../utils/Logs.sol";
import {SymbioticCoreConstants} from "../../../test/integration/SymbioticCoreConstants.sol";

import {AdapterRegistry} from "../../../src/contracts/AdapterRegistry.sol";
import {ProtocolFeeRegistry} from "../../../src/contracts/ProtocolFeeRegistry.sol";
import {UniversalDelegator} from "../../../src/contracts/delegator/UniversalDelegator.sol";
import {UniversalDelegatorFactory} from "../../../src/contracts/UniversalDelegatorFactory.sol";
import {VaultV2} from "../../../src/contracts/vault/VaultV2.sol";
import {WithdrawalQueue} from "../../../src/contracts/vault/WithdrawalQueue.sol";
import {WithdrawalQueueFactory} from "../../../src/contracts/WithdrawalQueueFactory.sol";

import {IMigratableEntity} from "../../../src/interfaces/common/IMigratableEntity.sol";
import {UNIVERSAL_DELEGATOR_VERSION} from "../../../src/interfaces/delegator/IUniversalDelegator.sol";

contract DeployV2BaseScript is Script {
    struct DeploymentData {
        SymbioticCoreConstants.Core core;
        AdapterRegistry adapterRegistry;
        ProtocolFeeRegistry protocolFeeRegistry;
        WithdrawalQueueFactory withdrawalQueueFactory;
        WithdrawalQueue withdrawalQueue;
        UniversalDelegatorFactory universalDelegatorFactory;
        VaultV2 vaultV2;
        UniversalDelegator universalDelegator;
    }

    function runBase(address owner) public virtual returns (DeploymentData memory data) {
        data = runBase(owner, owner);
    }

    function runBase(address adapterRegistryOwner, address protocolFeeRegistryOwner)
        public
        virtual
        returns (DeploymentData memory data)
    {
        require(adapterRegistryOwner != address(0), "invalid adapter registry owner");
        require(protocolFeeRegistryOwner != address(0), "invalid protocol fee registry owner");

        data.core = _core();

        _startBroadcast();
        address broadcaster = _scriptOwner();
        data.adapterRegistry = new AdapterRegistry(adapterRegistryOwner);
        data.protocolFeeRegistry = new ProtocolFeeRegistry(protocolFeeRegistryOwner);
        data.withdrawalQueueFactory = new WithdrawalQueueFactory(broadcaster);
        data.withdrawalQueue = new WithdrawalQueue(address(data.withdrawalQueueFactory));
        data.withdrawalQueueFactory.whitelist(address(data.withdrawalQueue));
        if (adapterRegistryOwner != broadcaster) {
            data.withdrawalQueueFactory.transferOwnership(adapterRegistryOwner);
        }
        data.universalDelegatorFactory = new UniversalDelegatorFactory(broadcaster);
        data.vaultV2 = new VaultV2(
            address(data.core.vaultFactory),
            address(data.universalDelegatorFactory),
            address(data.protocolFeeRegistry),
            address(data.withdrawalQueueFactory)
        );
        data.core.vaultFactory.whitelist(address(data.vaultV2));
        data.universalDelegator =
            new UniversalDelegator(address(data.adapterRegistry), address(data.universalDelegatorFactory));
        data.universalDelegatorFactory.whitelist(address(data.universalDelegator));
        if (adapterRegistryOwner != broadcaster) {
            data.universalDelegatorFactory.transferOwnership(adapterRegistryOwner);
        }
        _stopBroadcast();

        assert(data.adapterRegistry.owner() == adapterRegistryOwner);
        assert(data.protocolFeeRegistry.owner() == protocolFeeRegistryOwner);
        assert(data.withdrawalQueueFactory.owner() == adapterRegistryOwner);
        assert(data.universalDelegatorFactory.owner() == adapterRegistryOwner);
        assert(IMigratableEntity(address(data.vaultV2)).FACTORY() == address(data.core.vaultFactory));
        assert(IMigratableEntity(address(data.universalDelegator)).FACTORY() == address(data.universalDelegatorFactory));
        assert(data.core.vaultFactory.implementation(data.core.vaultFactory.lastVersion()) == address(data.vaultV2));
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
}
