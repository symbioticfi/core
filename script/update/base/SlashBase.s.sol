// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IVault} from "../../../src/interfaces/vault/IVault.sol";
import {ISlasher} from "../../../src/interfaces/slasher/ISlasher.sol";
import {Logs} from "../../utils/Logs.sol";
import {ScriptBase} from "../../utils/ScriptBase.s.sol";

contract SlashBaseScript is ScriptBase {
    function run(
        address vault,
        bytes32 subnetwork,
        address operator,
        uint256 amount,
        uint48 captureTimestamp
    ) public returns (bytes memory data, address target) {
        target = IVault(vault).slasher();
        data = abi.encodeCall(
            ISlasher(IVault(vault).slasher()).slash, (subnetwork, operator, amount, captureTimestamp, new bytes(0))
        );
        sendTransaction(target, data);

        Logs.log(
            string.concat(
                "Slash ",
                "\n    vault:",
                vm.toString(vault),
                "\n    subnetwork:",
                vm.toString(subnetwork),
                "\n    operator:",
                vm.toString(operator),
                "\n    amount:",
                vm.toString(amount),
                "\n    captureTimestamp:",
                vm.toString(captureTimestamp)
            )
        );
        Logs.logSimulationLink(target, data);

        return (data, target);
    }
}
