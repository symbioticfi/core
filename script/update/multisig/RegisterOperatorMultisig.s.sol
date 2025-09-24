// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../base/RegisterOperatorBase.s.sol";
import {Logs} from "../../utils/Logs.sol";

import {console2} from "forge-std/Test.sol";

// forge script script/update/multisig/RegisterOperatorMultisig.s.sol:RegisterOperatorMultisigScript --rpc-url=RPC --private-key PRIVATE_KEY --broadcast

contract RegisterOperatorMultisigScript is RegisterOperatorBaseScript {
    address public OPERATOR_REGISTRY = address(0);

    function run() public {
        (bytes memory data, address target) = run(OPERATOR_REGISTRY, false);
        Logs.log(
            string.concat(
                "RegisterOperator multisig data:", "\n    data:", vm.toString(data), "\n    target:", vm.toString(target)
            )
        );
    }
}
