// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/SetNetworkLimitBase.s.sol";
import {Subnetwork} from "../../../src/contracts/libraries/Subnetwork.sol";

// forge script script/actions/v1/SetNetworkLimit.s.sol:SetNetworkLimitScript --rpc-url=RPC --private-key PRIVATE_KEY --broadcast
// forge script script/actions/v1/SetNetworkLimit.s.sol:SetNetworkLimitScript --rpc-url=RPC -—sender MULTISIG_ADDRESS —-unlocked

contract SetNetworkLimitScript is SetNetworkLimitBaseScript {
    using Subnetwork for address;

    // Configuration constants - UPDATE THESE BEFORE EXECUTING

    // Address of the Vault
    address constant VAULT = 0x0000000000000000000000000000000000000000;
    // Address of the Network to set the network limit for
    address constant NETWORK = 0x0000000000000000000000000000000000000000;
    // Subnetwork Identifier
    uint96 constant IDENTIFIER = 0;
    // Network limit value to set
    uint256 constant LIMIT = 0;

    function run() public {
        (bytes memory data, address target) = runBase(VAULT, NETWORK.subnetwork(IDENTIFIER), LIMIT);
        Logs.log(
            string.concat(
                "SetNetworkLimit data:", "\n    data:", vm.toString(data), "\n    target:", vm.toString(target)
            )
        );
    }
}
