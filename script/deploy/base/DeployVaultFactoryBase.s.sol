// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {Logs} from "../../utils/Logs.sol";

import {VaultFactory} from "../../../src/contracts/VaultFactory.sol";

contract DeployVaultFactoryBaseScript is Script {
    function run(
        address owner
    ) public virtual {
        vm.startBroadcast();
        VaultFactory vaultFactory = new VaultFactory(owner);
        vm.stopBroadcast();

        Logs.log(string.concat("Deployed VaultFactory: ", vm.toString(address(vaultFactory))));
    }
}
