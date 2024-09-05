// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {OperatorRegistry} from "../../src/contracts/OperatorRegistry.sol";

import {MetadataService} from "../../src/contracts/service/MetadataService.sol";
import {IMetadataService} from "../../src/interfaces/service/IMetadataService.sol";

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract MetadataServiceTest is Test {
    using Strings for string;

    address owner;
    address alice;
    uint256 alicePrivateKey;
    address bob;
    uint256 bobPrivateKey;

    OperatorRegistry registry;

    IMetadataService service;

    function setUp() public {
        owner = address(this);
        (alice, alicePrivateKey) = makeAddrAndKey("alice");
        (bob, bobPrivateKey) = makeAddrAndKey("bob");

        registry = new OperatorRegistry();
    }

    function test_Create(
        string calldata metadataURL_
    ) public {
        vm.assume(!metadataURL_.equal(""));

        service = IMetadataService(address(new MetadataService(address(registry))));

        assertEq(service.metadataURL(alice), "");

        vm.startPrank(alice);
        registry.registerOperator();
        vm.stopPrank();

        vm.startPrank(alice);
        service.setMetadataURL(metadataURL_);
        vm.stopPrank();

        assertEq(service.metadataURL(alice), metadataURL_);
    }

    function test_SetMetadataURLRevertNotEntity(
        string calldata metadataURL_
    ) public {
        vm.assume(!metadataURL_.equal(""));

        service = IMetadataService(address(new MetadataService(address(registry))));

        vm.startPrank(alice);
        vm.expectRevert(IMetadataService.NotEntity.selector);
        service.setMetadataURL(metadataURL_);
        vm.stopPrank();
    }

    function test_SetMetadataURLRevertAlreadySet(
        string calldata metadataURL_
    ) public {
        vm.assume(!metadataURL_.equal(""));

        service = IMetadataService(address(new MetadataService(address(registry))));

        vm.startPrank(alice);
        registry.registerOperator();
        vm.stopPrank();

        vm.startPrank(alice);
        service.setMetadataURL(metadataURL_);
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(IMetadataService.AlreadySet.selector);
        service.setMetadataURL(metadataURL_);
        vm.stopPrank();
    }
}
