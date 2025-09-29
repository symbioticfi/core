// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/SetNetworkLimitBase.s.sol";

import {console2} from "forge-std/Test.sol";

// forge script script/update/SetNetworkLimit.s.sol:SetNetworkLimitScript --rpc-url=RPC --private-key PRIVATE_KEY --broadcast

contract SetNetworkLimitScript is SetNetworkLimitBaseScript {
    address public VAULT = address(0);
    bytes32 public SUBNETWORK = bytes32(0);
    uint256 public NETWORK_LIMIT = 0;

    function run() public {
        run(VAULT, SUBNETWORK, NETWORK_LIMIT);
    }
}
