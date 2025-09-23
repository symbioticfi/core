// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IVetoSlasher} from "../../../../src/interfaces/slasher/IVetoSlasher.sol";
import {IVault} from "../../../../src/interfaces/vault/IVault.sol";
import {Logs} from "../../../utils/Logs.sol";
import {MultisigBase} from "../../../utils/MultisigBase.sol";

contract ExecuteSlashMultisigBaseScript is MultisigBase {
    function run(address vault, uint256 slashIndex, address multisig, string memory chainAlias, string memory walletType) public {
        address[] memory targets = new address[](1);
        targets[0] = IVault(vault).slasher();
        bytes[] memory txns = new bytes[](1);
        txns[0] = abi.encodeCall(IVetoSlasher.executeSlash, (slashIndex, new bytes(0)));
        run(true, multisig, chainAlias, walletType, targets, txns);

        Logs.log(
            string.concat(
                "Proposed multisig to execute slash ", 
                "\n    slashIndex:", 
                vm.toString(slashIndex), 
                "\n    vault:", 
                vm.toString(vault)
            )
        );
    }

}
