// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../base/OptInVaultBase.s.sol";
import {Logs} from "../../utils/Logs.sol";

import {console2} from "forge-std/Test.sol";

// forge script script/update/multisig/OptInVaultMultisig.s.sol:OptInVaultMultisigScript --rpc-url=RPC -—sender SENDER_ADDRESS —-unlocked

contract OptInVaultMultisigScript is OptInVaultBaseScript {
    address public OPERATOR_VAULT_OPT_IN_SERVICE = address(0);
    address public VAULT = address(0);

    function run() public {
        (bytes memory data, address target) = run(OPERATOR_VAULT_OPT_IN_SERVICE, VAULT);
        Logs.log(
            string.concat(
                "OptInVault multisig data:", "\n    data:", vm.toString(data), "\n    target:", vm.toString(target)
            )
        );
    }
}
