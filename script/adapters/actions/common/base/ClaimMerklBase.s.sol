// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IMerklClaimer} from "../../../../../src/interfaces/adapters/common/IMerklClaimer.sol";
import {Logs} from "../../../../utils/Logs.sol";
import {ScriptBase} from "../../../../utils/ScriptBase.s.sol";

contract ClaimMerklBaseScript is ScriptBase {
    function runBase(address adapter, address[] memory tokens, uint256[] memory amounts, bytes32[][] memory proofs)
        public
        virtual
        returns (bytes memory data, address target)
    {
        target = adapter;
        data = abi.encodeCall(IMerklClaimer.claim, (tokens, amounts, proofs));
        sendTransaction(target, data);

        Logs.log(string.concat("Claim Merkl rewards", "\n    adapter:", vm.toString(adapter)));
        Logs.logSimulationLink(target, data);
    }
}
