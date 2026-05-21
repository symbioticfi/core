// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {Adapter} from "../../src/contracts/adapters/Adapter.sol";
import {AdapterFactory} from "../../src/contracts/adapters/AdapterFactory.sol";
import {MigratableEntityProxy} from "../../src/contracts/common/MigratableEntityProxy.sol";
import {Registry} from "../../src/contracts/common/Registry.sol";

import {IAdapter} from "../../src/interfaces/adapters/IAdapter.sol";
import {IMigratableEntity} from "../../src/interfaces/common/IMigratableEntity.sol";

import {Token} from "../mocks/Token.sol";

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

contract AdapterFactoryTest is Test {
    MockRegistry internal vaultFactory;
    AdapterFactory internal factory;
    MockAdapter internal implementation;
    Token internal collateral;

    address internal owner = makeAddr("owner");
    address internal curator = makeAddr("curator");
    address internal vault;

    function setUp() public {
        vaultFactory = new MockRegistry();
        factory = new AdapterFactory(owner);
        collateral = new Token("Collateral");
        vault = address(new MockVault(address(collateral)));
        implementation = new MockAdapter(address(vaultFactory), address(factory));

        vm.prank(owner);
        factory.whitelist(address(implementation));
    }

    function test_CreateRevertsForNonVault() public {
        vm.expectRevert(IAdapter.InvalidVault.selector);
        factory.create(1, curator, abi.encode(vault, ""));
    }

    function test_InitializeRevertsForNonVault() public {
        bytes memory data = abi.encode(vault, "");
        bytes memory initData = abi.encodeCall(IMigratableEntity.initialize, (1, curator, data));

        vm.expectRevert(IAdapter.InvalidVault.selector);
        new MigratableEntityProxy(address(implementation), initData);
    }

    function test_CreateUsesMigratablesFactorySaltAndInitializesAdapterVault() public {
        vaultFactory.add(vault);

        bytes memory data = abi.encode(vault, "");
        bytes memory initData = abi.encodeCall(IMigratableEntity.initialize, (1, curator, data));
        bytes memory initCode =
            abi.encodePacked(type(MigratableEntityProxy).creationCode, abi.encode(address(implementation), initData));
        address predicted = Create2.computeAddress(
            keccak256(abi.encode(uint256(0), uint64(1), curator, data)), keccak256(initCode), address(factory)
        );

        address adapter = factory.create(1, curator, data);

        assertEq(adapter, predicted);
        assertTrue(factory.isEntity(adapter));
        assertEq(IAdapter(adapter).vault(), vault);
        assertEq(IMigratableEntity(adapter).FACTORY(), address(factory));
        assertEq(IMigratableEntity(adapter).version(), 1);
    }

    function test_CreateAllowsMultipleAdaptersForSameVault() public {
        vaultFactory.add(vault);

        bytes memory data = abi.encode(vault, "");

        address firstAdapter = factory.create(1, curator, data);
        address secondAdapter = factory.create(1, curator, data);

        assertNotEq(firstAdapter, secondAdapter);
        assertTrue(factory.isEntity(firstAdapter));
        assertTrue(factory.isEntity(secondAdapter));
        assertEq(IAdapter(firstAdapter).vault(), vault);
        assertEq(IAdapter(secondAdapter).vault(), vault);
    }

    function test_SeparateFactoriesCanCreateForSameVault() public {
        vaultFactory.add(vault);

        AdapterFactory otherFactory = new AdapterFactory(owner);
        MockAdapter otherImplementation = new MockAdapter(address(vaultFactory), address(otherFactory));
        vm.prank(owner);
        otherFactory.whitelist(address(otherImplementation));

        address adapter = factory.create(1, curator, abi.encode(vault, ""));
        address otherAdapter = otherFactory.create(1, curator, abi.encode(vault, ""));

        assertNotEq(adapter, otherAdapter);
        assertEq(IAdapter(otherAdapter).vault(), vault);
    }
}

contract MockRegistry is Registry {
    function add(address entity) external {
        _addEntity(entity);
    }
}

contract MockAdapter is Adapter {
    constructor(address vaultFactory, address adapterFactory) Adapter(vaultFactory, adapterFactory, address(0)) {}

    function totalAssets() public view override returns (uint256) {
        return 0;
    }

    function allocatable() public view override returns (uint256) {
        return type(uint256).max;
    }

    function deallocatable() public view override returns (uint256) {
        return 0;
    }

    function _allocate(uint256 amount) internal override returns (uint256) {
        return amount;
    }

    function _deallocate(uint256) internal override returns (uint256) {
        return 0;
    }
}

contract MockVault {
    address public immutable asset;

    constructor(address asset_) {
        asset = asset_;
    }
}
