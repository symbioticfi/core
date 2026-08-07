// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";

import {AccountPause} from "./contracts/AccountPause.sol";

contract DeployAccountPauseScript is Script {
    error DeployAccountPauseScript__InvalidFactory();

    function run(address factory) public returns (address implementation) {
        if (factory == address(0)) {
            revert DeployAccountPauseScript__InvalidFactory();
        }

        vm.startBroadcast();
        implementation = address(new AccountPause(factory));
        vm.stopBroadcast();

        assert(AccountPause(payable(implementation)).FACTORY() == factory);
        console2.log("Deployed AccountPause:", implementation);
    }
}
