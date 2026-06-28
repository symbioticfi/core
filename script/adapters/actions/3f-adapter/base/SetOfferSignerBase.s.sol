// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IThreeFAdapter} from "../../../../../src/interfaces/adapters/IThreeFAdapter.sol";
import {Logs} from "../../../../utils/Logs.sol";
import {ScriptBase} from "../../../../utils/ScriptBase.s.sol";

contract SetOfferSignerBaseScript is ScriptBase {
    function runBase(address adapter, address signer) public virtual returns (bytes memory data, address target) {
        target = adapter;
        data = abi.encodeCall(IThreeFAdapter.setOfferSigner, (signer));
        sendTransaction(target, data);

        Logs.log(
            string.concat(
                "Set 3F offer signer", "\n    adapter:", vm.toString(adapter), "\n    signer:", vm.toString(signer)
            )
        );
        Logs.logSimulationLink(target, data);
    }
}
