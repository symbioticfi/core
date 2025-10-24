// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/OptInVaultBase.s.sol";

import {console2} from "forge-std/Test.sol";

// forge script script/actions/OptInVault.s.sol:OptInVaultScript --rpc-url=RPC --private-key PRIVATE_KEY --broadcast

contract OptInVaultScript is OptInVaultBaseScript {
    // Configuration constants - UPDATE THESE BEFORE EXECUTING

    // Address of the OperatorVaultOptInService contract
    address constant OPERATOR_VAULT_OPT_IN_SERVICE = address(0);
    // Address of the vault being opted into
    address constant VAULT = address(0);

    function run() public {
        run(OPERATOR_VAULT_OPT_IN_SERVICE, VAULT);
    }
}
