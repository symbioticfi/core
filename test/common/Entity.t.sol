// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {Factory} from "src/contracts/common/Factory.sol";
import {IFactory} from "src/interfaces/common/IFactory.sol";

import {IEntity} from "src/interfaces/common/IEntity.sol";

import {SimpleEntity} from "test/mocks/SimpleEntity.sol";

contract EntityTest is Test {
    address owner;
    address alice;
    uint256 alicePrivateKey;
    address bob;
    uint256 bobPrivateKey;

    IFactory factory;

    function setUp() public {
        owner = address(this);
        (alice, alicePrivateKey) = makeAddrAndKey("alice");
        (bob, bobPrivateKey) = makeAddrAndKey("bob");

        factory = new Factory(owner);
    }

    function test_Create() public {
        address impl = address(new SimpleEntity(address(factory)));
        assertEq(IEntity(impl).FACTORY(), address(factory));
        factory.whitelist(impl);

        address entity = factory.create(0, true, "");
        assertEq(IEntity(entity).FACTORY(), address(factory));

        vm.expectRevert();
        IEntity(entity).initialize("");
    }
}
