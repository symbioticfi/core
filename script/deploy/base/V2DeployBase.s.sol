// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {Logs} from "../../utils/Logs.sol";
import {SymbioticCoreConstants} from "../../../test/integration/SymbioticCoreConstants.sol";

import {AdapterRegistry} from "../../../src/contracts/AdapterRegistry.sol";
import {UniversalDelegator} from "../../../src/contracts/delegator/UniversalDelegator.sol";
import {VaultV2} from "../../../src/contracts/vault/VaultV2.sol";
import {WithdrawalQueue} from "../../../src/contracts/vault/WithdrawalQueue.sol";

import {IMigratableEntity} from "../../../src/interfaces/common/IMigratableEntity.sol";
import {UNIVERSAL_DELEGATOR_TYPE} from "../../../src/interfaces/delegator/IUniversalDelegator.sol";

contract V2DeployBaseScript is Script {
    struct DeploymentData {
        SymbioticCoreConstants.Core core;
        AdapterRegistry adapterRegistry;
        WithdrawalQueue withdrawalQueue;
        VaultV2 vaultV2;
        UniversalDelegator universalDelegator;
    }

    function runBase(address adapterRegistryOwner, address protocolFee, address rewards)
        public
        virtual
        returns (DeploymentData memory data)
    {
        require(adapterRegistryOwner != address(0), "invalid adapter registry owner");

        data.core = _core();

        _startBroadcast();
        data.adapterRegistry = new AdapterRegistry(adapterRegistryOwner);
        data.withdrawalQueue = new WithdrawalQueue();
        data.vaultV2 = new VaultV2(
            rewards,
            protocolFee,
            address(data.core.vaultFactory),
            address(data.core.slasherFactory),
            address(data.adapterRegistry),
            address(data.core.delegatorFactory),
            address(data.withdrawalQueue)
        );
        data.universalDelegator = new UniversalDelegator(
            UNIVERSAL_DELEGATOR_TYPE,
            address(data.core.vaultFactory),
            address(data.adapterRegistry),
            address(data.core.delegatorFactory)
        );
        _stopBroadcast();

        assert(data.adapterRegistry.owner() == adapterRegistryOwner);
        assert(IMigratableEntity(address(data.vaultV2)).FACTORY() == address(data.core.vaultFactory));
        assert(data.universalDelegator.TYPE() == UNIVERSAL_DELEGATOR_TYPE);

        Logs.log(string.concat("Deployed AdapterRegistry: ", vm.toString(address(data.adapterRegistry))));
        Logs.log(string.concat("Deployed WithdrawalQueue: ", vm.toString(address(data.withdrawalQueue))));
        Logs.log(string.concat("Deployed VaultV2: ", vm.toString(address(data.vaultV2))));
        Logs.log(string.concat("Deployed UniversalDelegator: ", vm.toString(address(data.universalDelegator))));
    }

    function _startBroadcast() internal virtual {
        vm.startBroadcast();
    }

    function _stopBroadcast() internal virtual {
        vm.stopBroadcast();
    }

    function _core() internal view virtual returns (SymbioticCoreConstants.Core memory) {
        return SymbioticCoreConstants.core();
    }
}
