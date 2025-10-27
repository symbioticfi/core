// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/SetHookBase.s.sol";

// forge script script/actions/SetHook.s.sol:SetHookScript --rpc-url=RPC --private-key PRIVATE_KEY --broadcast
// forge script script/actions/SetHook.s.sol:SetHookScript --rpc-url=RPC -—sender MULTISIG_ADDRESS —-unlocked

contract SetHookScript is SetHookBaseScript {
    // Configuration constants - UPDATE THESE BEFORE EXECUTING

    // Address of the Vault to update
    address constant VAULT = address(0);
    // Address of the hook contract to set
    address constant HOOK = address(0);

    function run() public {
        (bytes memory data, address target) = runBase(VAULT, HOOK);
        Logs.log(string.concat("SetHook data:", "\n    data:", vm.toString(data), "\n    target:", vm.toString(target)));
    }
}
