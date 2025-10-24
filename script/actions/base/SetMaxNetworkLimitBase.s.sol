// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IVault} from "../../../src/interfaces/vault/IVault.sol";
import {IBaseDelegator} from "../../../src/interfaces/delegator/IBaseDelegator.sol";
import {Logs} from "../../utils/Logs.sol";
import {ScriptBase} from "../../utils/ScriptBase.s.sol";

contract SetMaxNetworkLimitBaseScript is ScriptBase {
    function run(address vault, uint96 identifier, uint256 maxNetworkLimit)
        public
        returns (bytes memory data, address target)
    {
        target = IVault(vault).delegator();
        data =
            abi.encodeCall(IBaseDelegator(IVault(vault).delegator()).setMaxNetworkLimit, (identifier, maxNetworkLimit));
        sendTransaction(target, data);

        Logs.log(
            string.concat(
                "Set max network limit ",
                "\n    vault:",
                vm.toString(vault),
                "\n    identifier:",
                vm.toString(identifier),
                "\n    maxNetworkLimit:",
                vm.toString(maxNetworkLimit)
            )
        );
        Logs.logSimulationLink(target, data);

        return (data, target);
    }
}
