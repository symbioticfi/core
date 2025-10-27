// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/VetoSlashBase.s.sol";

// forge script script/actions/VetoSlash.s.sol:VetoSlashScript --rpc-url=RPC --private-key PRIVATE_KEY --broadcast
// forge script script/actions/VetoSlash.s.sol:VetoSlashScript --rpc-url=RPC -—sender MULTISIG_ADDRESS —-unlocked

contract VetoSlashScript is VetoSlashBaseScript {
    // Configuration constants - UPDATE THESE BEFORE EXECUTING

    // Address of the Vault that created the slash request
    address constant VAULT = address(0);
    // Index of the Slash Request to veto
    uint256 constant INDEX = 0;

    function run() public {
        (bytes memory data, address target) = runBase(VAULT, INDEX);
        Logs.log(
            string.concat("VetoSlash data:", "\n    data:", vm.toString(data), "\n    target:", vm.toString(target))
        );
    }
}
