// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";

import {BaseDelegator} from "../../src/contracts/delegator/BaseDelegator.sol";
import {IBaseDelegator} from "../../src/interfaces/delegator/IBaseDelegator.sol";

contract BaseDelegatorDefaultsHarness is BaseDelegator {
    constructor() BaseDelegator(address(1), address(2), address(3), address(4), address(5), 6) {}

    function exposeStakeAt(bytes32 subnetwork, address operator, uint48 timestamp, bytes memory hints)
        external
        view
        returns (uint256, bytes memory)
    {
        return _stakeAt(subnetwork, operator, timestamp, hints);
    }

    function exposeStake(bytes32 subnetwork, address operator) external view returns (uint256) {
        return _stake(subnetwork, operator);
    }

    function exposeSetMaxNetworkLimit(bytes32 subnetwork, uint256 amount) external {
        _setMaxNetworkLimit(subnetwork, amount);
    }

    function exposeInitializeHook(address vault_, bytes memory data)
        external
        returns (IBaseDelegator.BaseParams memory)
    {
        return __initialize(vault_, data);
    }
}

contract BaseDelegatorTest is Test {
    function test_DefaultHooksReturnZeroValues() public {
        BaseDelegatorDefaultsHarness delegator = new BaseDelegatorDefaultsHarness();

        (uint256 stakeAtValue, bytes memory baseHints) =
            delegator.exposeStakeAt(bytes32(uint256(1)), address(0xA), 10, "hints");
        assertEq(stakeAtValue, 0);
        assertEq(baseHints, "");
        assertEq(delegator.exposeStake(bytes32(uint256(2)), address(0xB)), 0);

        delegator.exposeSetMaxNetworkLimit(bytes32(uint256(3)), 99);

        IBaseDelegator.BaseParams memory params = delegator.exposeInitializeHook(address(0xC), "data");
        assertEq(params.defaultAdminRoleHolder, address(0));
        assertEq(params.hook, address(0));
        assertEq(params.hookSetRoleHolder, address(0));
    }
}
