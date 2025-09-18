// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../SymbioticCoreInit.sol";

import {console2} from "forge-std/Test.sol";

// forge script script/integration/examples/OptInVault.s.sol:OptInVaultScript --rpc-url=RPC --private-key PRIVATE_KEY --broadcast

contract OptInVaultScript is SymbioticCoreInit {
    address public VAULT = address(0);

    function run() public {
        (,, address txOrigin) = vm.readCallers();
        address OPERATOR = txOrigin;

        _optInVault_SymbioticCore(symbioticCore, OPERATOR, VAULT);
    }
}
