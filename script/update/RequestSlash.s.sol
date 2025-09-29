// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/RequestSlashBase.s.sol";

import {console2} from "forge-std/Test.sol";

// forge script script/update/RequestSlash.s.sol:RequestSlashScript --rpc-url=RPC --private-key PRIVATE_KEY --broadcast

contract RequestSlashScript is RequestSlashBaseScript {
    address public VAULT = address(0);
    bytes32 public SUBNETWORK = bytes32(0);
    address public OPERATOR = address(0);
    uint256 public AMOUNT = 0;
    uint48 public CAPTURE_TIMESTAMP = 0;

    function run() public {
        run(VAULT, SUBNETWORK, OPERATOR, AMOUNT, CAPTURE_TIMESTAMP);
    }
}
