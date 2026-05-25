// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {AaveV3Adapter} from "../../src/contracts/adapters/AaveV3Adapter.sol";
import {AdapterFactory} from "../../src/contracts/adapters/AdapterFactory.sol";
import {Registry} from "../../src/contracts/common/Registry.sol";

import {IAaveV3Adapter} from "../../src/interfaces/adapters/IAaveV3Adapter.sol";
import {IAdapter} from "../../src/interfaces/adapters/IAdapter.sol";

import {Token} from "../mocks/Token.sol";
import {MockAaveAToken, MockAavePool} from "../mocks/HoodiScenarioProtocolMocks.sol";

contract AaveV3AdapterTest is Test {
    AaveV3AdapterRegistryMock internal vaultFactory;
    AdapterFactory internal factory;
    Token internal collateral;
    MockAaveAToken internal aToken;
    MockAavePool internal pool;
    AaveV3AdapterVaultMock internal vault;
    IAaveV3Adapter internal adapter;

    address internal curator = makeAddr("curator");
    address internal delegator = makeAddr("delegator");

    function setUp() public {
        vaultFactory = new AaveV3AdapterRegistryMock();
        factory = new AdapterFactory(address(this));
        collateral = new Token("Collateral");
        aToken = new MockAaveAToken(address(collateral));
        pool = new MockAavePool(address(collateral), address(aToken), address(0));
        aToken.setPool(address(pool));
        vault = new AaveV3AdapterVaultMock(address(collateral), delegator);
        vaultFactory.add(address(vault));

        AaveV3Adapter implementation =
            new AaveV3Adapter(address(pool), address(vaultFactory), address(factory), address(0));
        factory.whitelist(address(implementation));

        adapter = IAaveV3Adapter(factory.create(1, curator, abi.encode(address(vault), "")));
    }

    function test_ViewsReturnZeroWithoutReserve() public {
        AaveV3AdapterVaultMock localVault = new AaveV3AdapterVaultMock(address(new Token("Other")), delegator);
        vaultFactory.add(address(localVault));
        IAaveV3Adapter localAdapter = IAaveV3Adapter(factory.create(1, curator, abi.encode(address(localVault), "")));

        assertEq(localAdapter.aToken(), address(0));
        assertEq(localAdapter.allocatable(), 0);
        assertEq(localAdapter.deallocatable(), 0);
        assertEq(localAdapter.totalAssets(), 0);
    }

    function test_AllocateAndDeallocateThroughAave() public {
        collateral.transfer(address(adapter), 100);

        vm.prank(delegator);
        uint256 allocated = adapter.allocate(100);

        assertEq(allocated, 100);
        assertEq(aToken.balanceOf(address(adapter)), 100);
        assertEq(adapter.totalAssets(), 100);
        assertEq(adapter.deallocatable(), 100);

        pool.setVirtualUnderlyingBalance(40);
        assertEq(adapter.deallocatable(), 40);

        vm.prank(delegator);
        uint256 deallocated = adapter.deallocate(70);

        assertEq(deallocated, 40);
        assertEq(collateral.balanceOf(address(adapter)), 40);
        assertEq(adapter.totalAssets(), 60);
    }

    function test_AllocateAndDeallocateReturnZeroForZeroAmount() public {
        vm.startPrank(delegator);
        assertEq(adapter.allocate(0), 0);
        assertEq(adapter.deallocate(0), 0);
        vm.stopPrank();
    }

    function test_AllocateReturnsZeroWhenSupplyReverts() public {
        collateral.transfer(address(adapter), 100);
        pool.setRevertOnSupply(true);

        vm.prank(delegator);
        uint256 allocated = adapter.allocate(100);

        assertEq(allocated, 0);
        assertEq(aToken.balanceOf(address(adapter)), 0);
        assertEq(collateral.balanceOf(address(adapter)), 100);
    }

    function test_DeallocateReturnsZeroWhenWithdrawRevertsOrNoLiquidity() public {
        collateral.transfer(address(adapter), 100);

        vm.prank(delegator);
        adapter.allocate(100);

        pool.setRevertOnWithdraw(true);

        vm.prank(delegator);
        assertEq(adapter.deallocate(100), 0);

        pool.setRevertOnWithdraw(false);
        pool.setVirtualUnderlyingBalance(0);

        vm.prank(delegator);
        assertEq(adapter.deallocate(100), 0);
    }

    function test_OnlyDelegatorCanMoveAssets() public {
        vm.expectRevert(IAdapter.NotVault.selector);
        adapter.allocate(1);

        vm.expectRevert(IAdapter.NotVault.selector);
        adapter.deallocate(1);

        vm.expectRevert(IAdapter.NotVault.selector);
        adapter.requestDeallocate(1);
    }
}

contract AaveV3AdapterRegistryMock is Registry {
    function add(address entity) external {
        _addEntity(entity);
    }
}

contract AaveV3AdapterVaultMock {
    address public immutable asset;
    address public delegator;

    constructor(address asset_, address delegator_) {
        asset = asset_;
        delegator = delegator_;
    }
}
