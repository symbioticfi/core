// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";

import {DefaultCollateralFactory} from "src/contracts/defaultCollateral/DefaultCollateralFactory.sol";

contract DefaultCollateralFactoryScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        new DefaultCollateralFactory();

        vm.stopBroadcast();
    }
}
