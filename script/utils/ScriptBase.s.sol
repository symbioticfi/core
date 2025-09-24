// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";

contract ScriptBase is Script {
    function sendTransaction(address target, bytes memory data) public virtual {
        vm.startBroadcast();
        (bool success,) = target.call(data);
        vm.stopBroadcast();
        if (!success) {
            revert("ExecuteSlash failed");
        }
    }
}
