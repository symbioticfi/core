// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IVaultV2} from "../../../../src/interfaces/vault/IVaultV2.sol";
import {Logs} from "../../../utils/Logs.sol";
import {ScriptBase} from "../../../utils/ScriptBase.s.sol";

contract SetPerformanceFeeBaseScript is ScriptBase {
    function runBase(address vault, uint96 fee, address receiver)
        public
        virtual
        returns (bytes memory data, address target)
    {
        target = vault;
        data = abi.encodeCall(IVaultV2.setPerformanceFee, (fee, receiver));
        sendTransaction(target, data);

        Logs.log(
            string.concat(
                "Set performance fee",
                "\n    vault:",
                vm.toString(vault),
                "\n    fee:",
                vm.toString(uint256(fee)),
                "\n    receiver:",
                vm.toString(receiver)
            )
        );
        Logs.logSimulationLink(target, data);
    }
}
