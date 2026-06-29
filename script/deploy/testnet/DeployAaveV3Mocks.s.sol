// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DeployAaveV3MocksBaseScript} from "./base/DeployAaveV3MocksBase.s.sol";

// forge script script/deploy/testnet/DeployAaveV3Mocks.s.sol:DeployAaveV3MocksScript --rpc-url RPC/hoodi --broadcast --verify --etherscan-api-key <>

contract DeployAaveV3MocksScript is DeployAaveV3MocksBaseScript {
    // Leave zero to deploy a new mock collateral, or replace with an existing collateral address.
    address public constant COLLATERAL = 0x0000000000000000000000000000000000000000;

    function run() public {
        runBase(vm.envOr("TESTNET_COLLATERAL", COLLATERAL));
    }
}
