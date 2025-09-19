// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console2} from "forge-std/Script.sol";

contract Logs is Script {
    string internal constant LOG_FILE = "script/logs.txt";

    function log(
        string memory data
    ) internal {
        console2.log(data);
        vm.writeFile(LOG_FILE, string.concat(vm.readFile(LOG_FILE), data, "\n"));
    }
}
