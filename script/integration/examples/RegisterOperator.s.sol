// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../SymbioticCoreInit.sol";

import {console2} from "forge-std/Test.sol";

// forge script script/integration/examples/RegisterOperator.s.sol:RegisterOperatorScript --rpc-url=RPC --private-key PRIVATE_KEY --broadcast

contract RegisterOperatorScript is SymbioticCoreInit {
    function run() public {
        (,, address txOrigin) = vm.readCallers();
        address OPERATOR = txOrigin;

        _registerOperator_SymbioticCore(symbioticCore, OPERATOR);
    }
}
