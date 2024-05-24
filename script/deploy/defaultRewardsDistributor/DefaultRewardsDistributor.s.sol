// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";

import {IDefaultRewardsDistributorFactory} from
    "src/interfaces/defaultRewardsDistributor/IDefaultRewardsDistributorFactory.sol";

contract DefaultRewardsDistributorScript is Script {
    function run(address defaultRewardsDistributorFactory, address vault) external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        IDefaultRewardsDistributorFactory(defaultRewardsDistributorFactory).create(vault);

        vm.stopBroadcast();
    }
}
