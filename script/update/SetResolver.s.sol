// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/SetResolverBase.s.sol";

import {console2} from "forge-std/Test.sol";

// forge script script/update/SetResolver.s.sol:SetResolverScript --rpc-url=RPC --private-key PRIVATE_KEY --broadcast

contract SetResolverScript is SetResolverBaseScript {
    address public VAULT = address(0);
    uint96 public IDENTIFIER = 0;
    address public RESOLVER = address(0);

    function run() public {
        run(VAULT, IDENTIFIER, RESOLVER, true);
    }
}
