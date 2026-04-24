// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/SetOperatorNetworkSharesBase.s.sol";
import {Subnetwork} from "../../src/contracts/libraries/Subnetwork.sol";

// forge script script/actions/SetOperatorNetworkShares.s.sol:SetOperatorNetworkSharesScript --rpc-url=RPC --private-key PRIVATE_KEY --broadcast
// forge script script/actions/SetOperatorNetworkShares.s.sol:SetOperatorNetworkSharesScript --rpc-url=RPC -—sender MULTISIG_ADDRESS —-unlocked

contract SetOperatorNetworkSharesScript is SetOperatorNetworkSharesBaseScript {
    using Subnetwork for address;

    // Configuration constants - UPDATE THESE BEFORE EXECUTING

    // Address of the Vault
    address constant VAULT = 0x0000000000000000000000000000000000000000;
    // Address of the Network to set the operator network shares for
    address constant NETWORK = 0x0000000000000000000000000000000000000000;
    // Subnetwork Identifier
    uint96 constant IDENTIFIER = 0;
    // Address of the Operator to set the operator network shares for
    address constant OPERATOR = 0x0000000000000000000000000000000000000000;
    // Operator-Network-specific shares
    uint256 constant SHARES = 0;

    function run() public {
        (bytes memory data, address target) = runBase(VAULT, NETWORK.subnetwork(IDENTIFIER), OPERATOR, SHARES);
        Logs.log(
            string.concat(
                "SetOperatorNetworkShares data:", "\n    data:", vm.toString(data), "\n    target:", vm.toString(target)
            )
        );
    }
}
