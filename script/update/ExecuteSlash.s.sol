// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/ExecuteSlashBase.s.sol";

import {console2} from "forge-std/Test.sol";

// forge script script/integration/examples/ExecuteSlash.s.sol:ExecuteSlashScript --rpc-url=RPC --private-key PRIVATE_KEY --broadcast

contract ExecuteSlashScript is ExecuteSlashBaseScript {
    address public VAULT = address(0);
    uint256 public SLASH_INDEX = 0;

    function run() public {
        run(VAULT, SLASH_INDEX, true);
    }
}
