// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {HoodiAdapterDependencyDeployBaseScript} from "./base/HoodiAdapterDependencyDeployBase.s.sol";

contract HoodiAdapterDependencyDeployScript is HoodiAdapterDependencyDeployBaseScript {
    bool public PREFER_LIVE_DEPENDENCIES = true;

    function run() public {
        runBase(PREFER_LIVE_DEPENDENCIES);
    }
}
