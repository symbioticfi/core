// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../base/SetOperatorNetworkSharesBase.s.sol";
import {Logs} from "../../utils/Logs.sol";

import {console2} from "forge-std/Test.sol";

// forge script script/update/multisig/SetOperatorNetworkSharesMultisig.s.sol:SetOperatorNetworkSharesMultisigScript --rpc-url=RPC --private-key PRIVATE_KEY --broadcast

contract SetOperatorNetworkSharesMultisigScript is SetOperatorNetworkSharesBaseScript {
    address public VAULT = 0x450a90fdEa8B87a6448Ca1C87c88Ff65676aC45b;
    bytes32 public SUBNETWORK = bytes32(0);
    address public OPERATOR = address(0);
    uint256 public OPERATOR_NETWORK_SHARES = 0;

    function run() public {
        (bytes memory data, address target) = run(VAULT, SUBNETWORK, OPERATOR, OPERATOR_NETWORK_SHARES, false);
        Logs.log(
            string.concat(
                "SetOperatorNetworkShares multisig data:", "\n    data:", vm.toString(data), "\n    target:", vm.toString(target)
            )
        );
    }
}
