// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IThreeFAdapter} from "../../../../../src/interfaces/adapters/IThreeFAdapter.sol";
import {Logs} from "../../../../utils/Logs.sol";
import {ScriptBase} from "../../../../utils/ScriptBase.s.sol";

contract RedeemThreeFRequestsBaseScript is ScriptBase {
    function runBase(address adapter, address[] memory requests)
        public
        virtual
        returns (bytes memory data, address target)
    {
        target = adapter;
        uint256 length = requests.length;
        for (uint256 i; i < length; ++i) {
            data = abi.encodeCall(IThreeFAdapter.finalizeRequest, (requests[i]));
            sendTransaction(target, data);
        }

        Logs.log(string.concat("Finalize 3F requests", "\n    adapter:", vm.toString(adapter)));
        Logs.logSimulationLink(target, data);
    }
}
