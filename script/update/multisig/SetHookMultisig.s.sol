// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../base/SetHookBase.s.sol";
import {Logs} from "../../utils/Logs.sol";

import {console2} from "forge-std/Test.sol";

// forge script script/update/multisig/SetHookMultisig.s.sol:SetHookMultisigScript --rpc-url=RPC -—sender SENDER_ADDRESS —-unlocked

contract SetHookMultisigScript is SetHookBaseScript {
    address public VAULT = 0x450a90fdEa8B87a6448Ca1C87c88Ff65676aC45b;
    address public HOOK = address(0);

    function run() public {
        (bytes memory data, address target) = run(VAULT, HOOK);
        Logs.log(
            string.concat(
                "SetHook multisig data:", "\n    data:", vm.toString(data), "\n    target:", vm.toString(target)
            )
        );
    }
}
