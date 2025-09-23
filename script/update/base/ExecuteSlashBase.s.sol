// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IVetoSlasher} from "../../../src/interfaces/slasher/IVetoSlasher.sol";
import {IVault} from "../../../src/interfaces/vault/IVault.sol";
import {Logs} from "../../utils/Logs.sol";

import {Script, console2} from "forge-std/Script.sol";

// forge script script/integration/examples/ExecuteSlash.s.sol:ExecuteSlashScript --rpc-url=RPC --private-key PRIVATE_KEY --broadcast

contract ExecuteSlashBaseScript is Script {
    function run(address vault, uint256 slashIndex) public {
        vm.startBroadcast();
        IVetoSlasher(IVault(vault).slasher()).executeSlash(slashIndex, new bytes(0));
        vm.stopBroadcast();

        Logs.log(
            string.concat(
                "Executed slash ", 
                "\n    slashIndex:", 
                vm.toString(slashIndex), 
                "\n    vault:", 
                vm.toString(vault)
            )
        );
    }
}
