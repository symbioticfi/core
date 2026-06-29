// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IThreeFAdapter} from "../../../../../src/interfaces/adapters/IThreeFAdapter.sol";
import {Logs} from "../../../../utils/Logs.sol";
import {ScriptBase} from "../../../../utils/ScriptBase.s.sol";

contract SetExposureLimitsBaseScript is ScriptBase {
    function runBase(
        address adapter,
        uint256 perRequestMaxCollateral,
        uint256 minRequestYield,
        uint256 maxConcurrentLoans
    ) public virtual returns (bytes memory data, address target) {
        target = adapter;
        data = abi.encodeCall(
            IThreeFAdapter.setExposureLimits, (perRequestMaxCollateral, minRequestYield, maxConcurrentLoans)
        );
        sendTransaction(target, data);

        Logs.log(
            string.concat(
                "Set 3F exposure limits",
                "\n    adapter:",
                vm.toString(adapter),
                "\n    perRequestMaxCollateral:",
                vm.toString(perRequestMaxCollateral),
                "\n    minRequestYield:",
                vm.toString(minRequestYield),
                "\n    maxConcurrentLoans:",
                vm.toString(maxConcurrentLoans)
            )
        );
        Logs.logSimulationLink(target, data);
    }
}
