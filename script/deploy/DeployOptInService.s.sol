// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {DeployOptInServiceBaseScript} from "./base/DeployOptInServiceBase.s.sol";

contract DeployOptInServiceScript is DeployOptInServiceBaseScript {
    address public WHO_REGISTRY = 0x0000000000000000000000000000000000000000;
    address public WHERE_REGISTRY = 0x0000000000000000000000000000000000000000;
    string public NAME = "";

    function run() public {
        DeployOptInServiceBaseScript.run(WHO_REGISTRY, WHERE_REGISTRY, NAME);
    }
}
