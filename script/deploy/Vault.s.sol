// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {IMigratablesRegistry} from "src/interfaces/base/IMigratablesRegistry.sol";
import {IVault} from "src/interfaces/IVault.sol";

contract VaultScript is Script {
    function run(
        address vaultRegistry,
        address owner,
        address collateral,
        uint48 epochDuration,
        uint48 vetoDuration,
        uint48 slashDuration,
        address rewardsDistributor,
        uint256 adminFee,
        bool depositWhitelist
    ) public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        IMigratablesRegistry(vaultRegistry).create(
            IMigratablesRegistry(vaultRegistry).lastVersion(),
            abi.encode(
                IVault.InitParams({
                    owner: owner,
                    collateral: collateral,
                    epochDuration: epochDuration,
                    vetoDuration: vetoDuration,
                    slashDuration: slashDuration,
                    rewardsDistributor: rewardsDistributor,
                    adminFee: adminFee,
                    depositWhitelist: depositWhitelist
                })
            )
        );

        vm.stopBroadcast();
    }
}
