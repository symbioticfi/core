// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../base/ExecuteSlashBase.s.sol";
import {Logs} from "../../utils/Logs.sol";

import {console2} from "forge-std/Test.sol";

// forge script script/integration/examples/ExecuteSlashMultisig.s.sol:ExecuteSlashMultisigScript --rpc-url=RPC --private-key PRIVATE_KEY --broadcast

contract ExecuteSlashMultisigScript is ExecuteSlashBaseScript {
    address public VAULT = 0x450a90fdEa8B87a6448Ca1C87c88Ff65676aC45b;
    uint256 public SLASH_INDEX = 0;

    function run() public {
        (bytes memory data, address target) = run(VAULT, SLASH_INDEX, false);
        Logs.log(
            string.concat(
                "ExecuteSlash multisig data:", "\n    data:", vm.toString(data), "\n    target:", vm.toString(target)
            )
        );
    }
}
