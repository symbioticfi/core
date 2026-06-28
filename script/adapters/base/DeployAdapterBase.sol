// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {AdapterFactory} from "../../../src/contracts/adapters/AdapterFactory.sol";
import {IMigratableEntity} from "../../../src/interfaces/common/IMigratableEntity.sol";
import {Logs} from "../../utils/Logs.sol";
import {SymbioticCoreConstants} from "../../../test/integration/SymbioticCoreConstants.sol";

contract DeployAdapterBase is Script {
    struct DeploymentData {
        address adapterFactory;
        address adapterImplementation;
    }

    function _deployAdapterFactory() internal returns (address adapterFactory) {
        adapterFactory = address(new AdapterFactory(_scriptOwner()));
    }

    function _whitelistAndTransferOwnership(DeploymentData memory data, address adapterFactoryOwner) internal {
        AdapterFactory(data.adapterFactory).whitelist(data.adapterImplementation);

        if (adapterFactoryOwner != _scriptOwner()) {
            Ownable(data.adapterFactory).transferOwnership(adapterFactoryOwner);
        }
    }

    function _validateAdapterDeployment(DeploymentData memory data, address adapterFactoryOwner) internal view {
        assert(Ownable(data.adapterFactory).owner() == adapterFactoryOwner);
        assert(IMigratableEntity(data.adapterImplementation).FACTORY() == data.adapterFactory);
        assert(AdapterFactory(data.adapterFactory).implementation(1) == data.adapterImplementation);
    }

    function _logDeployment(string memory name, DeploymentData memory data) internal {
        Logs.log(
            string.concat(
                "Deployed ",
                name,
                " adapter factory",
                "\n    adapterFactory:",
                vm.toString(data.adapterFactory),
                "\n    adapterImplementation:",
                vm.toString(data.adapterImplementation)
            )
        );
    }

    function _validateAdapterFactoryOwner(address adapterFactoryOwner) internal pure {
        require(adapterFactoryOwner != address(0), "invalid adapter factory owner");
    }

    function _scriptOwner() internal view virtual returns (address owner_) {
        (,, address origin) = vm.readCallers();
        return origin == address(0) ? msg.sender : origin;
    }

    function _coreVaultFactory() internal view virtual returns (address) {
        return address(SymbioticCoreConstants.core().vaultFactory);
    }

    function _startBroadcast() internal virtual {
        vm.startBroadcast();
    }

    function _stopBroadcast() internal virtual {
        vm.stopBroadcast();
    }
}
