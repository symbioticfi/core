// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IVault} from "../../../src/interfaces/vault/IVault.sol";
import {ISlasher} from "../../../src/interfaces/slasher/ISlasher.sol";
import {Logs} from "../../utils/Logs.sol";
import {ScriptBase} from "../../utils/ScriptBase.s.sol";

contract SlashBaseScript is ScriptBase {
    function runBase(address vault, bytes32 subnetwork, address operator, uint256 amount)
        public
        virtual
        returns (bytes memory data, address target)
    {
        target = IVault(vault).slasher();
        data = abi.encodeCall(ISlasher.slash, (subnetwork, operator, amount, 0, new bytes(0)));
        sendTransaction(target, data);

        Logs.log(
            string.concat(
                "Slash",
                "\n    vault:",
                vm.toString(vault),
                "\n    subnetwork:",
                vm.toString(subnetwork),
                "\n    operator:",
                vm.toString(operator),
                "\n    amount:",
                vm.toString(amount)
            )
        );
        Logs.logSimulationLink(target, data);

        return (data, target);
    }
}
