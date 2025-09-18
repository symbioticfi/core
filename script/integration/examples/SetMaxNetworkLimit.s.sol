// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../SymbioticCoreInit.sol";

import {console2} from "forge-std/Test.sol";

// forge script script/integration/examples/SetMaxNetworkLimit.s.sol:SetMaxNetworkLimitScript --rpc-url=RPC --private-key PRIVATE_KEY --broadcast

contract SetMaxNetworkLimitScript is SymbioticCoreInit {
    address public VAULT = address(0);
    uint96 public IDENTIFIER = 0;
    uint256 public MAX_NETWORK_LIMIT = 0;

    function run() public {
        (,, address txOrigin) = vm.readCallers();
        address NETWORK = txOrigin;

        _setMaxNetworkLimit_SymbioticCore(NETWORK, VAULT, IDENTIFIER, MAX_NETWORK_LIMIT);
    }
}
