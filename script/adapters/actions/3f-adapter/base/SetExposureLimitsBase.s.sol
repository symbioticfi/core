// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IThreeFAdapter} from "../../../../../src/interfaces/adapters/IThreeFAdapter.sol";
import {Logs} from "../../../../utils/Logs.sol";
import {ScriptBase} from "../../../../utils/ScriptBase.s.sol";

contract SetExposureLimitsBaseScript is ScriptBase {
    function runBase(
        address adapter,
        uint256 minYieldPerRequest,
        uint256 minAssetsPerRequest,
        uint256 maxAssetsPerRequest
    ) public virtual returns (bytes memory data, address target) {
        target = adapter;
        data = abi.encodeCall(
            IThreeFAdapter.setLimitsPerRequest, (minYieldPerRequest, minAssetsPerRequest, maxAssetsPerRequest)
        );
        sendTransaction(target, data);

        Logs.log(
            string.concat(
                "Set 3F per-request limits",
                "\n    adapter:",
                vm.toString(adapter),
                "\n    minYieldPerRequest:",
                vm.toString(minYieldPerRequest),
                "\n    minAssetsPerRequest:",
                vm.toString(minAssetsPerRequest),
                "\n    maxAssetsPerRequest:",
                vm.toString(maxAssetsPerRequest)
            )
        );
        Logs.logSimulationLink(target, data);
    }
}
