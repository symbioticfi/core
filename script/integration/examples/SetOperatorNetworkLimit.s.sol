// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../SymbioticCoreInit.sol";

import {console2} from "forge-std/Test.sol";

// forge script script/integration/examples/SetOperatorNetworkLimit.s.sol:SetOperatorNetworkLimitScript --rpc-url=RPC --private-key PRIVATE_KEY --broadcast

contract SetOperatorNetworkLimitScript is SymbioticCoreInit {
    address public VAULT = address(0);
    bytes32 public SUBNETWORK = bytes32(0);
    address public OPERATOR = address(0);
    uint256 public AMOUNT = 0;

    function run() public {
        (,, address txOrigin) = vm.readCallers();
        address CURATOR = txOrigin;

        _setOperatorNetworkLimit_SymbioticCore(CURATOR, VAULT, SUBNETWORK, OPERATOR, AMOUNT);
    }
}
