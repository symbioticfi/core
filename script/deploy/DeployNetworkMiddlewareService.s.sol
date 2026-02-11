// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {DeployNetworkMiddlewareServiceBaseScript} from "./base/DeployNetworkMiddlewareServiceBase.s.sol";

contract DeployNetworkMiddlewareServiceScript is DeployNetworkMiddlewareServiceBaseScript {
    address public NETWORK_REGISTRY = 0x0000000000000000000000000000000000000000;

    function run() public {
        DeployNetworkMiddlewareServiceBaseScript.run(NETWORK_REGISTRY);
    }
}
