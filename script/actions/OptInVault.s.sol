// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/OptInVaultBase.s.sol";

// forge script script/actions/OptInVault.s.sol:OptInVaultScript --rpc-url=RPC --private-key PRIVATE_KEY --broadcast
// forge script script/actions/OptInVault.s.sol:OptInVaultScript --rpc-url=RPC -—sender MULTISIG_ADDRESS —-unlocked

contract OptInVaultScript is OptInVaultBaseScript {
    // Configuration constants - UPDATE THESE BEFORE EXECUTING

    // Address of the Vault to opt into
    address constant VAULT = address(0);

    function run() public {
        (bytes memory data, address target) = runBase(VAULT);
        Logs.log(
            string.concat("OptInVault data:", "\n    data:", vm.toString(data), "\n    target:", vm.toString(target))
        );
    }
}
