// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ScriptBase} from "../../../script/utils/ScriptBase.s.sol";

abstract contract ScriptBaseHarness is ScriptBase {
    address internal immutable broadcaster;

    constructor(address broadcaster_) {
        broadcaster = broadcaster_;
    }

    function sendTransaction(address target, bytes memory data) public virtual override {
        vm.prank(broadcaster);
        (bool success,) = target.call(data);
        require(success, "transaction failed");
    }
}
