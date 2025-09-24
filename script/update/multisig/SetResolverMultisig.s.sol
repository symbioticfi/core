// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../base/SetResolverBase.s.sol";
import {Logs} from "../../utils/Logs.sol";

import {console2} from "forge-std/Test.sol";

// forge script script/update/multisig/SetResolverMultisig.s.sol:SetResolverMultisigScript --rpc-url=RPC --private-key PRIVATE_KEY --broadcast

contract SetResolverMultisigScript is SetResolverBaseScript {
    address public VAULT = 0x450a90fdEa8B87a6448Ca1C87c88Ff65676aC45b;
    uint96 public IDENTIFIER = 0;
    address public RESOLVER = address(0);

    function run() public {
        (bytes memory data, address target) = run(VAULT, IDENTIFIER, RESOLVER, false);
        Logs.log(
            string.concat(
                "SetResolver multisig data:", "\n    data:", vm.toString(data), "\n    target:", vm.toString(target)
            )
        );
    }
}
