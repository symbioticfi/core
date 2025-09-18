// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../SymbioticCoreInit.sol";

import {console2} from "forge-std/Test.sol";

// forge script script/integration/examples/VetoSlash.s.sol:VetoSlashScript --rpc-url=RPC --private-key PRIVATE_KEY --broadcast

contract VetoSlashScript is SymbioticCoreInit {
    address public VAULT = address(0);
    uint256 public SLASH_INDEX = 0;

    function run() public {
        (,, address txOrigin) = vm.readCallers();
        address VETOER = txOrigin;

        _vetoSlash_SymbioticCore(VETOER, VAULT, SLASH_INDEX);
    }
}
