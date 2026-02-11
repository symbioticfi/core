// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console2} from "forge-std/Script.sol";

import {BaseDelegatorHints} from "../../../src/contracts/hints/DelegatorHints.sol";
import {BaseSlasherHints} from "../../../src/contracts/hints/SlasherHints.sol";
import {VaultHints} from "../../../src/contracts/hints/VaultHints.sol";
import {OptInServiceHints} from "../../../src/contracts/hints/OptInServiceHints.sol";
import {Logs} from "../../utils/Logs.sol";
import {SymbioticCoreConstants} from "../../../test/integration/SymbioticCoreConstants.sol";

contract DeployHintsBaseScript is Script {
    function run() public virtual {
        vm.startBroadcast();
        OptInServiceHints optInServiceHints = new OptInServiceHints();
        VaultHints vaultHints = new VaultHints();
        SymbioticCoreConstants.Core memory core = SymbioticCoreConstants.core();
        BaseDelegatorHints baseDelegatorHints = new BaseDelegatorHints(
            address(optInServiceHints),
            address(vaultHints),
            address(core.operatorVaultOptInService),
            address(core.operatorNetworkOptInService)
        );
        BaseSlasherHints baseSlasherHints = new BaseSlasherHints(address(baseDelegatorHints));
        vm.stopBroadcast();

        Logs.log(string.concat("Deployed OptInServiceHints: ", vm.toString(address(optInServiceHints))));
        Logs.log(string.concat("Deployed VaultHints: ", vm.toString(address(vaultHints))));
        Logs.log(string.concat("Deployed BaseDelegatorHints: ", vm.toString(address(baseDelegatorHints))));
        Logs.log(string.concat("Deployed SlasherHints: ", vm.toString(address(baseSlasherHints.SLASHER_HINTS()))));
        Logs.log(
            string.concat("Deployed VetoSlasherHints: ", vm.toString(address(baseSlasherHints.VETO_SLASHER_HINTS())))
        );
    }
}
