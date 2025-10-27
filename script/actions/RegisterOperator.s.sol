// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/RegisterOperatorBase.s.sol";

// forge script script/actions/RegisterOperator.s.sol:RegisterOperatorScript --rpc-url=RPC --private-key PRIVATE_KEY --broadcast

contract RegisterOperatorScript is RegisterOperatorBaseScript {
    // Configuration constants - UPDATE THESE BEFORE EXECUTING

    // Address of the OperatorRegistry contract
    address constant OPERATOR_REGISTRY = address(0);

    function run() public {
        run(OPERATOR_REGISTRY);
    }
}
