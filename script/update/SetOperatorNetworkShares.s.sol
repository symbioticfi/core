// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/SetOperatorNetworkSharesBase.s.sol";

import {console2} from "forge-std/Test.sol";

// forge script script/update/SetOperatorNetworkShares.s.sol:SetOperatorNetworkSharesScript --rpc-url=RPC --private-key PRIVATE_KEY --broadcast

contract SetOperatorNetworkSharesScript is SetOperatorNetworkSharesBaseScript {
    address public VAULT = address(0);
    bytes32 public SUBNETWORK = bytes32(0);
    address public OPERATOR = address(0);
    uint256 public OPERATOR_NETWORK_SHARES = 0;

    function run() public {
        run(VAULT, SUBNETWORK, OPERATOR, OPERATOR_NETWORK_SHARES);
    }
}
