// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {DeployMetadataServiceBaseScript} from "./base/DeployMetadataServiceBase.s.sol";

contract DeployMetadataServiceScript is DeployMetadataServiceBaseScript {
    address public REGISTRY = 0x0000000000000000000000000000000000000000;

    function run() public {
        DeployMetadataServiceBaseScript.run(REGISTRY);
    }
}
