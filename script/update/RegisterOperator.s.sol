// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/RegisterOperatorBase.s.sol";

import {console2} from "forge-std/Test.sol";

// forge script script/update/RegisterOperator.s.sol:RegisterOperatorScript --rpc-url=RPC --private-key PRIVATE_KEY --broadcast

contract RegisterOperatorScript is RegisterOperatorBaseScript {
    address public OPERATOR_REGISTRY = address(0);

    function run() public {
        run(OPERATOR_REGISTRY, true);
    }
}
