// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {DeployCoreBaseScript} from "./base/DeployCoreBase.s.sol";

contract DeployCoreScript is DeployCoreBaseScript {
    address public OWNER = 0x0000000000000000000000000000000000000000;

    function run() public {
        run(OWNER);
    }
}
