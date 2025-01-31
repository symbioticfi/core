// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Script, console2} from "forge-std/Script.sol";

import {BaseDelegatorHints} from "../../src/contracts/hints/DelegatorHints.sol";
import {BaseSlasherHints} from "../../src/contracts/hints/SlasherHints.sol";
import {VaultHints} from "../../src/contracts/hints/VaultHints.sol";
import {OptInServiceHints} from "../../src/contracts/hints/OptInServiceHints.sol";

contract HintsScript is Script {
    function run() public {
        vm.startBroadcast();

        OptInServiceHints optInServiceHints = new OptInServiceHints();
        VaultHints vaultHints = new VaultHints();
        BaseDelegatorHints baseDelegatorHints = new BaseDelegatorHints(address(optInServiceHints), address(vaultHints));
        BaseSlasherHints baseSlasherHints = new BaseSlasherHints(address(baseDelegatorHints));

        console2.log("OptInServiceHints: ", address(optInServiceHints));
        console2.log("VaultHints: ", address(vaultHints));
        console2.log("BaseDelegatorHints: ", address(baseDelegatorHints));
        console2.log("SlasherHints: ", address(baseSlasherHints.SLASHER_HINTS()));
        console2.log("VetoSlasherHints: ", address(baseSlasherHints.VETO_SLASHER_HINTS()));

        vm.stopBroadcast();
    }
}
