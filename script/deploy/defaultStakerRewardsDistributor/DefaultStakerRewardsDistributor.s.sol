// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";

import {IDefaultStakerRewardsDistributorFactory} from
    "src/interfaces/defaultStakerRewardsDistributor/IDefaultStakerRewardsDistributorFactory.sol";

contract DefaultStakerRewardsDistributorScript is Script {
    function run(address defaultStakerRewardsDistributorFactory, address vault) external {
        vm.startBroadcast();

        IDefaultStakerRewardsDistributorFactory(defaultStakerRewardsDistributorFactory).create(vault);

        vm.stopBroadcast();
    }
}
