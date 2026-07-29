// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";

import {AdapterPause} from "./contracts/AdapterPause.sol";

contract DeployAdapterPauseScript is Script {
    error DeployAdapterPauseScript__InvalidFactory();

    function run(address factory) public returns (address implementation) {
        if (factory == address(0)) {
            revert DeployAdapterPauseScript__InvalidFactory();
        }

        vm.startBroadcast();
        implementation = address(new AdapterPause(factory));
        vm.stopBroadcast();

        assert(AdapterPause(payable(implementation)).FACTORY() == factory);
        console2.log("Deployed AdapterPause:", implementation);
    }
}
