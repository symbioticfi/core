// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {POCBaseTest} from "./POCBase.t.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Subnetwork} from "../src/contracts/libraries/Subnetwork.sol";

contract POCTest is POCBaseTest {
    using Math for uint256;
    using Subnetwork for bytes32;
    using Subnetwork for address;

    function setUp() public override {
        // There are 4 initially deployed Vaults:
        // 1. With NetworkRestakeDelegator, with Slasher - 7 days vault epoch (can be used with vault1, delegator1, slasher1 variables)
        // 2. With FullRestakeDelegator, with Slasher - 7 days vault epoch (can be used with vault2, delegator2, slasher2 variables)
        // 3. With NetworkRestakeDelegator, with VetoSlasher - 7 days vault epoch, 1 day veto period (can be used with vault3, delegator3, slasher3 variables)
        // 4. With FullRestakeDelegator, with VetoSlasher - 7 days vault epoch, 1 day veto period (can be used with vault4, delegator4, slasher4 variables)
        // For other deployments or interacting with these ones, you may use predefined functions in the POCBaseTest contract.

        SYMBIOTIC_CORE_PROJECT_ROOT = "";

        super.setUp();
    }

    function test_POC() public {}
}
