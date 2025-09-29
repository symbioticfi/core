// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/SetHookBase.s.sol";

import {console2} from "forge-std/Test.sol";

// forge script script/update/SetHook.s.sol:SetHookScript --rpc-url=RPC --private-key PRIVATE_KEY --broadcast

contract SetHookScript is SetHookBaseScript {
    address public VAULT = address(0);
    address public HOOK = address(0);

    function run() public {
        run(VAULT, HOOK);
    }
}
