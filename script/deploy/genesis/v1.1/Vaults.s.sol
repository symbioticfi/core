// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Script, console2} from "forge-std/Script.sol";

import {SymbioticCoreInit} from "../../../integration/SymbioticCoreInit.sol";

import {Vault} from "../../../../src/contracts/vault/v1.1/Vault.sol";
import {VaultTokenized} from "../../../../src/contracts/vault/v1.1/VaultTokenized.sol";
import {VaultVotes} from "../../../../src/contracts/vault/v1.1/VaultVotes.sol";
import {VaultImplementation} from "../../../../src/contracts/vault/v1.1/VaultImplementation.sol";
import {VaultTokenizedImplementation} from "../../../../src/contracts/vault/v1.1/VaultTokenizedImplementation.sol";
import {VaultVotesImplementation} from "../../../../src/contracts/vault/v1.1/VaultVotesImplementation.sol";

contract VaultsScript is SymbioticCoreInit {
    function run() public {
        SymbioticCoreInit.run(0);

        vm.startBroadcast();

        address vaultImplementation = address(
            new VaultImplementation(address(symbioticCore.delegatorFactory), address(symbioticCore.slasherFactory))
        );
        address vaultImpl = address(new Vault(address(symbioticCore.vaultFactory), vaultImplementation));

        address vaultTokenizedImplementation = address(new VaultTokenizedImplementation(vaultImplementation));
        address vaultTokenizedImpl =
            address(new VaultTokenized(address(symbioticCore.vaultFactory), vaultTokenizedImplementation));

        address vaultVotesImplementation = address(new VaultVotesImplementation(vaultImplementation));
        address vaultVotesImpl = address(new VaultVotes(address(symbioticCore.vaultFactory), vaultVotesImplementation));

        console2.log("Vault: ", address(vaultImpl));
        console2.log("VaultTokenized: ", address(vaultTokenizedImpl));
        console2.log("VaultVotes: ", address(vaultVotesImpl));
        console2.log();
        console2.log("VaultImplementation: ", address(vaultImplementation));
        console2.log("VaultTokenizedImplementation: ", address(vaultTokenizedImplementation));
        console2.log("VaultVotesImplementation: ", address(vaultVotesImplementation));

        vm.stopBroadcast();
    }
}
