// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SymbioticCoreBindingsBase} from "../../test/integration/base/SymbioticCoreBindingsBase.sol";

contract SymbioticCoreBindingsScript is SymbioticCoreBindingsBase {
    modifier broadcast(
        address who
    ) virtual override {
        vm.startBroadcast(who);
        _;
        vm.stopBroadcast();
    }
}
