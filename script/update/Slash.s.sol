// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/SlashBase.s.sol";

import {console2} from "forge-std/Test.sol";

// forge script script/update/Slash.s.sol:SlashScript --rpc-url=RPC --private-key PRIVATE_KEY --broadcast

contract SlashScript is SlashBaseScript {
    address public VAULT = address(0);
    bytes32 public SUBNETWORK = bytes32(0);
    address public OPERATOR = address(0);
    uint256 public AMOUNT = 0;
    uint48 public CAPTURE_TIMESTAMP = 0;

    function run() public {
        run(VAULT, SUBNETWORK, OPERATOR, AMOUNT, CAPTURE_TIMESTAMP, true);
    }
}
