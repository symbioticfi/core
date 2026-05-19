// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAdapter} from "../../../src/interfaces/adapters/IAdapter.sol";
import {Logs} from "../../utils/Logs.sol";
import {ScriptBase} from "../../utils/ScriptBase.s.sol";

contract SetGlobalLimitBaseScript is ScriptBase {
    function runBase(address adapter, address asset, uint256 limit)
        public
        virtual
        returns (bytes memory data, address target)
    {
        target = adapter;
        data = abi.encodeCall(IAdapter.setGlobalLimit, (asset, limit));
        sendTransaction(target, data);

        Logs.log(
            string.concat(
                "Set global adapter limit",
                "\n    adapter:",
                vm.toString(adapter),
                "\n    asset:",
                vm.toString(asset),
                "\n    limit:",
                vm.toString(limit)
            )
        );
        Logs.logSimulationLink(target, data);
    }
}
