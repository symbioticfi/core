// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ICoWSwapConverter} from "../../../../../src/interfaces/adapters/common/ICoWSwapConverter.sol";
import {Logs} from "../../../../utils/Logs.sol";
import {ScriptBase} from "../../../../utils/ScriptBase.s.sol";

contract SetConvertersBaseScript is ScriptBase {
    function runBase(address adapter, address[] memory converters)
        public
        virtual
        returns (bytes memory data, address target)
    {
        target = adapter;
        data = abi.encodeCall(ICoWSwapConverter.setConverters, (converters));
        sendTransaction(target, data);

        Logs.log(string.concat("Set adapter converters", "\n    adapter:", vm.toString(adapter)));
        Logs.logSimulationLink(target, data);
    }
}
