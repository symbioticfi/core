// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {INetworkMiddlewareService} from "../../../../src/interfaces/service/INetworkMiddlewareService.sol";
import {Logs} from "../../../utils/Logs.sol";
import {ScriptBase} from "../../../utils/ScriptBase.s.sol";

contract SetMiddlewareBaseScript is ScriptBase {
    function runBase(address service, address middleware) public virtual returns (bytes memory data, address target) {
        target = service;
        data = abi.encodeCall(INetworkMiddlewareService.setMiddleware, (middleware));
        sendTransaction(target, data);

        Logs.log(
            string.concat(
                "Set middleware", "\n    service:", vm.toString(service), "\n    middleware:", vm.toString(middleware)
            )
        );
        Logs.logSimulationLink(target, data);

        return (data, target);
    }
}
