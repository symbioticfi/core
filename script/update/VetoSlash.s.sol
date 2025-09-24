// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/VetoSlashBase.s.sol";

import {console2} from "forge-std/Test.sol";

// forge script script/update/VetoSlash.s.sol:VetoSlashScript --rpc-url=RPC --private-key PRIVATE_KEY --broadcast

contract VetoSlashScript is VetoSlashBaseScript {
    address public VAULT = address(0);
    uint256 public SLASH_INDEX = 0;

    function run() public {
        run(VAULT, SLASH_INDEX, true);
    }
}
