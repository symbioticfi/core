// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";

import {DefaultStakerRewardsDistributor} from
    "src/contracts/defaultStakerRewardsDistributor/DefaultStakerRewardsDistributor.sol";
import {DefaultStakerRewardsDistributorFactory} from
    "src/contracts/defaultStakerRewardsDistributor/DefaultStakerRewardsDistributorFactory.sol";

contract DefaultStakerRewardsDistributorFactoryScript is Script {
    function run(address networkRegistry, address vaultFactory, address networkMiddlewareService) external {
        vm.startBroadcast();

        DefaultStakerRewardsDistributor stakerRewardsDistributorImplementation =
            new DefaultStakerRewardsDistributor(networkRegistry, vaultFactory, networkMiddlewareService);
        new DefaultStakerRewardsDistributorFactory(address(stakerRewardsDistributorImplementation));

        vm.stopBroadcast();
    }
}
