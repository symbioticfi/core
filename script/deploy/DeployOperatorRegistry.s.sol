// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {DeployOperatorRegistryBaseScript} from "./base/DeployOperatorRegistryBase.s.sol";

contract DeployOperatorRegistryScript is DeployOperatorRegistryBaseScript {
    function run() public override {
        DeployOperatorRegistryBaseScript.run();
    }
}
