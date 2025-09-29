// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/OptInVaultBase.s.sol";

import {console2} from "forge-std/Test.sol";

// forge script script/update/OptInVault.s.sol:OptInVaultScript --rpc-url=RPC --private-key PRIVATE_KEY --broadcast

contract OptInVaultScript is OptInVaultBaseScript {
    address public OPERATOR_VAULT_OPT_IN_SERVICE = address(0);
    address public VAULT = address(0);

    function run() public {
        run(OPERATOR_VAULT_OPT_IN_SERVICE, VAULT);
    }
}
