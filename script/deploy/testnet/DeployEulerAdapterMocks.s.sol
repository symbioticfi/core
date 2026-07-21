// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DeployEulerAdapterMocksBaseScript} from "./base/DeployEulerAdapterMocksBase.s.sol";

// forge script script/deploy/testnet/DeployEulerAdapterMocks.s.sol:DeployEulerAdapterMocksScript --rpc-url RPC/hoodi --broadcast --verify --etherscan-api-key <>

contract DeployEulerAdapterMocksScript is DeployEulerAdapterMocksBaseScript {
    // Leave zero to deploy a new mock collateral, or replace with an existing collateral address.
    address public constant COLLATERAL = 0x0000000000000000000000000000000000000000;

    function run() public {
        runBase(vm.envOr("TESTNET_COLLATERAL", COLLATERAL));
    }
}
