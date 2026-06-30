// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IVaultV2} from "../../../../src/interfaces/vault/IVaultV2.sol";
import {IWithdrawalQueue} from "../../../../src/interfaces/vault/IWithdrawalQueue.sol";
import {Logs} from "../../../utils/Logs.sol";
import {ScriptBase} from "../../../utils/ScriptBase.s.sol";

contract RequestRedeemBaseScript is ScriptBase {
    function runBase(address vault, uint256 shares, address receiver)
        public
        virtual
        returns (bytes memory data, address target)
    {
        target = IVaultV2(vault).withdrawalQueue();
        data = abi.encodeCall(IWithdrawalQueue.requestRedeem, (shares, receiver));
        sendTransaction(target, data);

        Logs.log(
            string.concat(
                "Request redeem",
                "\n    vault:",
                vm.toString(vault),
                "\n    shares:",
                vm.toString(shares),
                "\n    receiver:",
                vm.toString(receiver)
            )
        );
        Logs.logSimulationLink(target, data);
    }
}
