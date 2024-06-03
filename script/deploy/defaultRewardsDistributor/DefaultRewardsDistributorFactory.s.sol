// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";

import {DefaultRewardsDistributorFactory} from
    "src/contracts/defaultRewardsDistributor/DefaultRewardsDistributorFactory.sol";

contract DefaultRewardsDistributorFactoryScript is Script {
    function run(address networkRegistry, address vaultFactory, address networkMiddlewareService) external {
        vm.startBroadcast();

        new DefaultRewardsDistributorFactory(networkRegistry, vaultFactory, networkMiddlewareService);

        vm.stopBroadcast();
    }
}
