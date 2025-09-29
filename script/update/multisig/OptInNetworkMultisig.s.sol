// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../base/OptInNetworkBase.s.sol";
import {Logs} from "../../utils/Logs.sol";

import {console2} from "forge-std/Test.sol";

// forge script script/update/multisig/OptInNetworkMultisig.s.sol:OptInNetworkMultisigScript --rpc-url=RPC -—sender SENDER_ADDRESS —-unlocked

contract OptInNetworkMultisigScript is OptInNetworkBaseScript {
    address public OPERATOR_NETWORK_OPT_IN_SERVICE = address(0);
    address public NETWORK = address(0);

    function run() public {
        (bytes memory data, address target) = run(OPERATOR_NETWORK_OPT_IN_SERVICE, NETWORK);
        Logs.log(
            string.concat(
                "OptInNetwork multisig data:", "\n    data:", vm.toString(data), "\n    target:", vm.toString(target)
            )
        );
    }
}
