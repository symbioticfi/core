// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AaveV3MocksDeployBaseScript} from "./base/AaveV3MocksDeployBase.s.sol";

// forge script script/deploy/testnet/AaveV3MocksDeploy.s.sol:AaveV3MocksDeployScript --rpc-url https://ethereum-rpc.gprptest.net/hoodi --broadcast --verify --etherscan-api-key 5NEH7KHHDWPQSEXNXJT3YSVBSS67MXRFXE

contract AaveV3MocksDeployScript is AaveV3MocksDeployBaseScript {
    // Leave zero to deploy a new mock collateral, or replace with an existing collateral address.
    address public constant COLLATERAL = 0x0000000000000000000000000000000000000000;

    function run() public {
        runBase(COLLATERAL);
    }
}
