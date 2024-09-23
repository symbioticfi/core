// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {IRegistry} from "../../src/interfaces/common/IRegistry.sol";

import {MigratablesFactory} from "../../src/contracts/common/MigratablesFactory.sol";
import {IMigratablesFactory} from "../../src/interfaces/common/IMigratablesFactory.sol";

import {IMigratableEntity} from "../../src/interfaces/common/IMigratableEntity.sol";

import {MigratableEntityProxy} from "../../src/contracts/common/MigratableEntityProxy.sol";

import {SimpleMigratableEntity} from "../mocks/SimpleMigratableEntity.sol";
import {SimpleMigratableEntityV2} from "../mocks/SimpleMigratableEntityV2.sol";

contract MigratableEntityProxyTest is Test {
    address owner;
    address alice;
    uint256 alicePrivateKey;
    address bob;
    uint256 bobPrivateKey;

    IMigratablesFactory factory;

    function setUp() public {
        owner = address(this);
        (alice, alicePrivateKey) = makeAddrAndKey("alice");
        (bob, bobPrivateKey) = makeAddrAndKey("bob");

        factory = new MigratablesFactory(owner);
    }

    function test_MigrateRevertProxyDeniedAdminAccess() public {
        address impl = address(new SimpleMigratableEntity(address(factory)));
        factory.whitelist(impl);

        address entity = factory.create(1, alice, "");

        address implV2 = address(new SimpleMigratableEntityV2(address(factory)));
        factory.whitelist(implV2);

        vm.startPrank(alice);
        vm.expectRevert(MigratableEntityProxy.ProxyDeniedAdminAccess.selector);
        MigratableEntityProxy(payable(entity)).upgradeToAndCall(implV2, "");
        vm.stopPrank();
    }
}
