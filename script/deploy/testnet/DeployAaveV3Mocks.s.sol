// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {DeployAaveV3MocksBaseScript} from "./base/DeployAaveV3MocksBase.s.sol";

// forge script script/deploy/testnet/DeployAaveV3Mocks.s.sol:DeployAaveV3MocksScript --rpc-url RPC/hoodi --broadcast --verify --etherscan-api-key 5NEH7KHHDWPQSEXNXJT3YSVBSS67MXRFXE

contract DeployAaveV3MocksScript is DeployAaveV3MocksBaseScript {
    // Leave zero to deploy a new mock collateral, or replace with an existing collateral address.
    address public constant COLLATERAL = 0x0000000000000000000000000000000000000000;

    function run() public {
        runBase(COLLATERAL);
    }
}
