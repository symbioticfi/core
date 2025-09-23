// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {console2} from "forge-std/console2.sol";
import {Vm} from "forge-std/Vm.sol";

library Logs {
    string internal constant LOG_FILE = "script/logs.txt";
    address internal constant VM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));
    Vm internal constant vm = Vm(VM_ADDRESS);

    function log(
        string memory data
    ) public {
        console2.log(data);
        vm.writeFile(LOG_FILE, string.concat(vm.readFile(LOG_FILE), data, "\n"));
    }
}
