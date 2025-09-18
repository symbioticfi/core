// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../SymbioticCoreInit.sol";

import {console2} from "forge-std/Test.sol";

// forge script script/integration/examples/SetOperatorNetworkShares.s.sol:SetOperatorNetworkSharesScript --rpc-url=RPC --private-key PRIVATE_KEY --broadcast

contract SetOperatorNetworkSharesScript is SymbioticCoreInit {
    using SymbioticSubnetwork for address;

    address public NETWORK = address(0);
    uint96 public IDENTIFIER = 0;
    bytes32 public SUBNETWORK = NETWORK.subnetwork(IDENTIFIER);
    address public VAULT = address(0);
    address public OPERATOR = address(0);
    uint256 public OPERATOR_NETWORK_SHARES = 0;

    function run() public {
        (,, address txOrigin) = vm.readCallers();
        address CURATOR = txOrigin;

        _setOperatorNetworkShares_SymbioticCore(CURATOR, VAULT, SUBNETWORK, OPERATOR, OPERATOR_NETWORK_SHARES);
    }
}
