// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";

import {IDefaultRewardsDistributorFactory} from
    "src/interfaces/defaultRewardsDistributor/IDefaultRewardsDistributorFactory.sol";

contract DefaultRewardsDistributorScript is Script {
    function run(address defaultRewardsDistributorFactory, address vault) external {
        vm.startBroadcast();

        IDefaultRewardsDistributorFactory(defaultRewardsDistributorFactory).create(vault);

        vm.stopBroadcast();
    }
}
