// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/ExecuteSlashBase.s.sol";

import {console2} from "forge-std/Test.sol";

// forge script script/actions/ExecuteSlash.s.sol:ExecuteSlashScript --rpc-url=RPC --private-key PRIVATE_KEY --broadcast

contract ExecuteSlashScript is ExecuteSlashBaseScript {
    // Configuration constants - UPDATE THESE BEFORE EXECUTING

    // Address of the Vault
    address constant VAULT = address(0);
    // Index of the slash request
    uint256 constant SLASH_INDEX = 0;

    function run() public {
        run(VAULT, SLASH_INDEX);
    }
}
