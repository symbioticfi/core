// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../SymbioticCoreInit.sol";

import {console2} from "forge-std/Test.sol";

// forge script script/integration/examples/SetResolver.s.sol:SetResolverScript --rpc-url=RPC --private-key PRIVATE_KEY --broadcast

contract SetResolverScript is SymbioticCoreInit {
    address public VAULT = address(0);
    uint96 public IDENTIFIER = 0;
    address public RESOLVER = address(0);

    function run() public {
        (,, address txOrigin) = vm.readCallers();
        address NETWORK = txOrigin;

        _setResolver_SymbioticCore(NETWORK, VAULT, IDENTIFIER, RESOLVER);
    }
}
