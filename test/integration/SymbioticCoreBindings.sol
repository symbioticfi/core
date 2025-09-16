// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SymbioticCoreBindingsBase} from "./base/SymbioticCoreBindingsBase.sol";

contract SymbioticCoreBindings is SymbioticCoreBindingsBase {
    modifier broadcast(
        address who
    ) virtual override {
        vm.startPrank(who);
        _;
        vm.stopPrank();
    }
}
