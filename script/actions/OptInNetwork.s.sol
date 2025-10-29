// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/OptInNetworkBase.s.sol";

// forge script script/actions/OptInNetwork.s.sol:OptInNetworkScript --rpc-url=RPC --private-key PRIVATE_KEY --broadcast
// forge script script/actions/OptInNetwork.s.sol:OptInNetworkScript --rpc-url=RPC -—sender MULTISIG_ADDRESS —-unlocked

contract OptInNetworkScript is OptInNetworkBaseScript {
    // Configuration constants - UPDATE THESE BEFORE EXECUTING

    // Address of the Network to opt into
    address constant NETWORK = address(0);

    function run() public {
        (bytes memory data, address target) = runBase(NETWORK);
        Logs.log(
            string.concat("OptInNetwork data:", "\n    data:", vm.toString(data), "\n    target:", vm.toString(target))
        );
    }
}
