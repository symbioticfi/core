// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IVaultV2} from "../../../../src/interfaces/vault/IVaultV2.sol";
import {IWithdrawalQueue} from "../../../../src/interfaces/vault/IWithdrawalQueue.sol";
import {Logs} from "../../../utils/Logs.sol";
import {ScriptBase} from "../../../utils/ScriptBase.s.sol";

contract ClaimWithdrawalBaseScript is ScriptBase {
    function runBase(address vault, uint256 tokenId, address receiver)
        public
        virtual
        returns (bytes memory data, address target)
    {
        target = IVaultV2(vault).withdrawalQueue();
        data = abi.encodeCall(IWithdrawalQueue.claim, (tokenId, receiver));
        sendTransaction(target, data);

        Logs.log(
            string.concat(
                "Claim withdrawal",
                "\n    vault:",
                vm.toString(vault),
                "\n    tokenId:",
                vm.toString(tokenId),
                "\n    receiver:",
                vm.toString(receiver)
            )
        );
        Logs.logSimulationLink(target, data);
    }
}
