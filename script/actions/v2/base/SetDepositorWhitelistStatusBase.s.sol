// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IVaultV2} from "../../../../src/interfaces/vault/IVaultV2.sol";
import {Logs} from "../../../utils/Logs.sol";
import {ScriptBase} from "../../../utils/ScriptBase.s.sol";

contract SetDepositorWhitelistStatusBaseScript is ScriptBase {
    function runBase(address vault, address account, bool status)
        public
        virtual
        returns (bytes memory data, address target)
    {
        target = vault;
        data = abi.encodeCall(IVaultV2.setDepositorWhitelistStatus, (account, status));
        sendTransaction(target, data);

        Logs.log(
            string.concat(
                "Set depositor whitelist status",
                "\n    vault:",
                vm.toString(vault),
                "\n    account:",
                vm.toString(account),
                "\n    status:",
                vm.toString(status)
            )
        );
        Logs.logSimulationLink(target, data);
    }
}
