// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {LiquidLaneRegistry} from "../../src/contracts/adapters/LiquidLaneRegistry.sol";

import {ILiquidLaneRegistry} from "../../src/interfaces/adapters/ILiquidLaneRegistry.sol";

contract LiquidLaneRegistryTest is Test {
    LiquidLaneRegistry internal registry;

    address internal owner = makeAddr("owner");
    address internal tokenToRedeem = makeAddr("tokenToRedeem");
    address internal accountFactory = makeAddr("accountFactory");

    function setUp() public {
        registry = new LiquidLaneRegistry(owner);
    }

    function test_SetAccountFactoryStoresFactory() public {
        vm.expectEmit(true, true, true, true, address(registry));
        emit ILiquidLaneRegistry.SetAccountFactory(tokenToRedeem, accountFactory);

        vm.prank(owner);
        registry.setAccountFactory(tokenToRedeem, accountFactory);

        assertEq(registry.accountFactories(tokenToRedeem), accountFactory);
    }
}
