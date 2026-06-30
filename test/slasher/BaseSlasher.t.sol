// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";

import {BaseSlasher} from "../../src/contracts/slasher/BaseSlasher.sol";
import {IBaseSlasher} from "../../src/interfaces/slasher/IBaseSlasher.sol";

contract BaseSlasherDefaultsHarness is BaseSlasher {
    constructor() BaseSlasher(address(1), address(2), address(3), 4) {}

    function exposeInitializeHook(address vault_, bytes memory data) external returns (IBaseSlasher.BaseParams memory) {
        return __initialize(vault_, data);
    }
}

contract BaseSlasherTest is Test {
    function test_DefaultInitializeHookReturnsZeroValues() public {
        BaseSlasherDefaultsHarness slasher = new BaseSlasherDefaultsHarness();

        IBaseSlasher.BaseParams memory params = slasher.exposeInitializeHook(address(0xD), "data");
        assertFalse(params.isBurnerHook);
    }
}
