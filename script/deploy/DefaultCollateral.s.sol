// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";

import {IDefaultCollateralFactory} from "src/interfaces/defaultCollateral/IDefaultCollateralFactory.sol";

contract DefaultCollateralScript is Script {
    function run(
        address defaultCollateralFactory,
        address asset,
        uint256 initialLimit,
        address limitIncreaser
    ) external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        IDefaultCollateralFactory(defaultCollateralFactory).create(asset, initialLimit, limitIncreaser);

        vm.stopBroadcast();
    }
}
