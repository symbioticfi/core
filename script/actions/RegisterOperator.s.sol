// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/RegisterOperatorBase.s.sol";

// forge script script/actions/RegisterOperator.s.sol:RegisterOperatorScript --rpc-url=RPC --private-key PRIVATE_KEY --broadcast
// forge script script/actions/RegisterOperator.s.sol:RegisterOperatorScript --rpc-url=RPC -—sender MULTISIG_ADDRESS —-unlocked

contract RegisterOperatorScript is RegisterOperatorBaseScript {
    // Configuration constants - UPDATE THESE BEFORE EXECUTING

    // Nothing to configure

    function run() public {
        (bytes memory data, address target) = runBase();
        Logs.log(
            string.concat(
                "RegisterOperator data:", "\n    data:", vm.toString(data), "\n    target:", vm.toString(target)
            )
        );
    }
}
