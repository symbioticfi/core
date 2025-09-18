// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../SymbioticCoreInit.sol";

import {console2} from "forge-std/Test.sol";

// forge script script/integration/examples/SetHook.s.sol:SetHookScript --rpc-url=RPC --private-key PRIVATE_KEY --broadcast

contract SetHookScript is SymbioticCoreInit {
    address public VAULT = address(0);
    address public HOOK = address(0);

    function run() public {
        (,, address txOrigin) = vm.readCallers();
        address CURATOR = txOrigin;

        _setHook_SymbioticCore(CURATOR, VAULT, HOOK);
    }
}
