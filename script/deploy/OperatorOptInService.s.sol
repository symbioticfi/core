// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {OperatorOptInService} from "src/contracts/OperatorOptInService.sol";

contract OperatorOptInServiceScript is Script {
    function run(address operatorRegistry, address vaultFactory) public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        new OperatorOptInService(operatorRegistry, vaultFactory);

        vm.stopBroadcast();
    }
}
