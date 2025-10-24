// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/SetHookBase.s.sol";

import {console2} from "forge-std/Test.sol";

// forge script script/actions/SetHook.s.sol:SetHookScript --rpc-url=RPC --private-key PRIVATE_KEY --broadcast

contract SetHookScript is SetHookBaseScript {
    // Configuration constants - UPDATE THESE BEFORE EXECUTING

    // Address of the vault to update
    address constant VAULT = address(0);
    // Address of the hook contract to set
    address constant HOOK = address(0);

    function run() public {
        run(VAULT, HOOK);
    }
}
