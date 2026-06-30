// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {DeployVaultFactoryBaseScript} from "./base/DeployVaultFactoryBase.s.sol";

contract DeployVaultFactoryScript is DeployVaultFactoryBaseScript {
    address public OWNER = 0x0000000000000000000000000000000000000000;

    function run() public {
        DeployVaultFactoryBaseScript.run(OWNER);
    }
}
