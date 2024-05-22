// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {IMigratablesRegistry} from "src/interfaces/base/IMigratablesRegistry.sol";
import {IVaultStorage} from "src/interfaces/IVaultStorage.sol";

contract VaultScript is Script {
    function run(
        address vaultRegistry,
        address owner,
        address collateral,
        uint48 epochDuration,
        uint48 vetoDuration,
        uint48 slashDuration,
        string memory metadataURL,
        uint256 adminFee,
        bool depositWhitelist
    ) public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        IMigratablesRegistry(vaultRegistry).create(
            IMigratablesRegistry(vaultRegistry).lastVersion(),
            abi.encode(
                IVaultStorage.InitParams({
                    owner: owner,
                    collateral: collateral,
                    epochDuration: epochDuration,
                    vetoDuration: vetoDuration,
                    slashDuration: slashDuration,
                    metadataURL: metadataURL,
                    adminFee: adminFee,
                    depositWhitelist: depositWhitelist
                })
            )
        );

        vm.stopBroadcast();
    }
}
