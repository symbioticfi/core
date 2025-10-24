// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/VetoSlashBase.s.sol";

import {console2} from "forge-std/Test.sol";

// forge script script/actions/VetoSlash.s.sol:VetoSlashScript --rpc-url=RPC --private-key PRIVATE_KEY --broadcast

contract VetoSlashScript is VetoSlashBaseScript {
    // Configuration constants - UPDATE THESE BEFORE EXECUTING

    // Address of the vault that created the slash request
    address constant VAULT = address(0);
    // Index of the slash request to veto
    uint256 constant SLASH_INDEX = 0;

    function run() public {
        run(VAULT, SLASH_INDEX);
    }
}
