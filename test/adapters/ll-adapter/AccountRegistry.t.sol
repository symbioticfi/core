// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {AccountRegistry} from "../../../src/contracts/adapters/ll-adapter/AccountRegistry.sol";

import {IAccountRegistry} from "../../../src/interfaces/adapters/ll-adapter/IAccountRegistry.sol";

contract AccountRegistryTest is Test {
    AccountRegistry internal registry;

    address internal owner = makeAddr("owner");
    address internal asset = makeAddr("asset");
    address internal tokenToRedeem = makeAddr("tokenToRedeem");
    address internal accountFactory = makeAddr("accountFactory");

    function setUp() public {
        registry = new AccountRegistry(owner);
    }

    function test_SetAccountFactoryStoresFactory() public {
        vm.expectEmit(true, true, true, true, address(registry));
        emit IAccountRegistry.SetAccountFactory(asset, tokenToRedeem, accountFactory);

        vm.prank(owner);
        registry.setAccountFactory(asset, tokenToRedeem, accountFactory);

        assertEq(registry.accountFactories(asset, tokenToRedeem), accountFactory);
    }

    function test_SetAccountFactoryRevertsIfAlreadySet() public {
        vm.startPrank(owner);
        registry.setAccountFactory(asset, tokenToRedeem, accountFactory);
        vm.expectRevert(IAccountRegistry.AccountFactoryAlreadySet.selector);
        registry.setAccountFactory(asset, tokenToRedeem, makeAddr("otherAccountFactory"));
        vm.stopPrank();
    }

    function test_MigratablesFactoryApiIsUnavailable() public {
        (bool lastVersionSuccess,) = address(registry).call(abi.encodeWithSignature("lastVersion()"));

        assertFalse(lastVersionSuccess);
    }
}
