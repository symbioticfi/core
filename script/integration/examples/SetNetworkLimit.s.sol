// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../SymbioticCoreInit.sol";

import {console2} from "forge-std/Test.sol";

// forge script script/integration/examples/SetNetworkLimit.s.sol:SetNetworkLimitScript --rpc-url=RPC --private-key PRIVATE_KEY --broadcast

contract SetNetworkLimitScript is SymbioticCoreInit {
    using SymbioticSubnetwork for address;

    address public NETWORK = address(0);
    uint96 public IDENTIFIER = 0;
    bytes32 public SUBNETWORK = NETWORK.subnetwork(IDENTIFIER);
    address public VAULT = address(0);
    uint256 public NETWORK_LIMIT = 0;

    function run() public {
        (,, address txOrigin) = vm.readCallers();
        address CURATOR = txOrigin;

        _setNetworkLimit_SymbioticCore(CURATOR, VAULT, SUBNETWORK, NETWORK_LIMIT);
    }
}
