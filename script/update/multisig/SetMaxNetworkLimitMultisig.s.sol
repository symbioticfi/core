// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../base/SetMaxNetworkLimitBase.s.sol";
import {Logs} from "../../utils/Logs.sol";

import {console2} from "forge-std/Test.sol";

// forge script script/update/multisig/SetMaxNetworkLimitMultisig.s.sol:SetMaxNetworkLimitMultisigScript --rpc-url=RPC -—sender SENDER_ADDRESS —-unlocked

contract SetMaxNetworkLimitMultisigScript is SetMaxNetworkLimitBaseScript {
    address public VAULT = 0x450a90fdEa8B87a6448Ca1C87c88Ff65676aC45b;
    uint96 public IDENTIFIER = 0;
    uint256 public MAX_NETWORK_LIMIT = 0;

    function run() public {
        (bytes memory data, address target) = run(VAULT, IDENTIFIER, MAX_NETWORK_LIMIT);
        Logs.log(
            string.concat(
                "SetMaxNetworkLimit multisig data:",
                "\n    data:",
                vm.toString(data),
                "\n    target:",
                vm.toString(target)
            )
        );
    }
}
