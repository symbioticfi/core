// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {VaultFactory} from "../../src/contracts/VaultFactory.sol";
import {DelegatorFactory} from "../../src/contracts/DelegatorFactory.sol";
import {SlasherFactory} from "../../src/contracts/SlasherFactory.sol";
import {VaultConfigurator} from "../../src/contracts/VaultConfigurator.sol";

import {Vault} from "../../src/contracts/vault/Vault.sol";
import {UniversalDelegator} from "../../src/contracts/delegator/UniversalDelegator.sol";

import {UniversalDelegatorIndex} from "../../src/contracts/libraries/UniversalDelegatorIndex.sol";

import {IBaseDelegator} from "../../src/interfaces/delegator/IBaseDelegator.sol";
import {IUniversalDelegator} from "../../src/interfaces/delegator/IUniversalDelegator.sol";
import {IVault} from "../../src/interfaces/vault/IVault.sol";
import {IVaultConfigurator} from "../../src/interfaces/IVaultConfigurator.sol";

import {Token} from "../mocks/Token.sol";

contract UniversalDelegatorTest is Test {
    using UniversalDelegatorIndex for uint96;

    uint48 internal constant EPOCH_DURATION = 3;

    address internal owner;
    address internal alice;
    address internal bob;

    VaultFactory internal vaultFactory;
    DelegatorFactory internal delegatorFactory;
    SlasherFactory internal slasherFactory;
    VaultConfigurator internal vaultConfigurator;

    Token internal collateral;
    Vault internal vault;
    UniversalDelegator internal delegator;

    function setUp() public {
        vm.warp(0);

        owner = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        vaultFactory = new VaultFactory(owner);
        delegatorFactory = new DelegatorFactory(owner);
        slasherFactory = new SlasherFactory(owner);

        address vaultImpl =
            address(new Vault(address(delegatorFactory), address(slasherFactory), address(vaultFactory)));
        vaultFactory.whitelist(vaultImpl);

        address delegatorImpl = address(
            new UniversalDelegator(
                address(0x1111),
                address(vaultFactory),
                address(0x2222),
                address(0x3333),
                address(delegatorFactory),
                delegatorFactory.totalTypes()
            )
        );
        delegatorFactory.whitelist(delegatorImpl);

        collateral = new Token("Token");
        vaultConfigurator =
            new VaultConfigurator(address(vaultFactory), address(delegatorFactory), address(slasherFactory));

        (address vault_, address delegator_,) = vaultConfigurator.create(
            IVaultConfigurator.InitParams({
                version: vaultFactory.lastVersion(),
                owner: owner,
                vaultParams: abi.encode(
                    IVault.InitParams({
                        collateral: address(collateral),
                        burner: address(0xdEaD),
                        epochDuration: EPOCH_DURATION,
                        depositWhitelist: false,
                        isDepositLimit: false,
                        depositLimit: 0,
                        defaultAdminRoleHolder: owner,
                        depositWhitelistSetRoleHolder: address(0),
                        depositorWhitelistRoleHolder: address(0),
                        isDepositLimitSetRoleHolder: address(0),
                        depositLimitSetRoleHolder: address(0)
                    })
                ),
                delegatorIndex: 0,
                delegatorParams: abi.encode(
                    IUniversalDelegator.InitParams({
                        baseParams: IBaseDelegator.BaseParams({
                            defaultAdminRoleHolder: address(0), hook: address(0), hookSetRoleHolder: address(0)
                        }),
                        curatorRoleHolder: owner
                    })
                ),
                withSlasher: false,
                slasherIndex: 0,
                slasherParams: ""
            })
        );

        vault = Vault(vault_);
        delegator = UniversalDelegator(delegator_);
    }

    function test_checkpointTracksHistory_andDefaults() public {
        delegator.createSlot(0, false, 30);
        uint96 slot1 = uint96(0).createIndex(uint32(1));

        assertEq(delegator.getAllocatedAt(slot1, 0, ""), 0);

        vm.warp(5);
        _deposit(alice, 100);
        assertEq(delegator.getAllocatedAt(slot1, 5, ""), 30);

        vm.warp(7);
        delegator.setSize(slot1, 20);
        assertEq(delegator.getAllocatedAt(slot1, 7, ""), 20);
        assertEq(delegator.getAllocatedAt(slot1, 9, ""), 20);
    }

    function test_slotAllocation_partialFill() public {
        _deposit(alice, 100);

        delegator.createSlot(0, false, 30);
        delegator.createSlot(0, false, 500);

        uint96 slot1 = uint96(0).createIndex(uint32(1));
        uint96 slot2 = uint96(0).createIndex(uint32(2));

        assertEq(delegator.getUnallocated(0), 0);
        assertEq(delegator.getAllocated(slot1), 30);
        assertEq(delegator.getAllocated(slot2), 70);
    }

    function test_slotAllocation_partialFill_2() public {
        _deposit(alice, 100);

        delegator.createSlot(0, false, 500);
        delegator.createSlot(0, false, 30);

        uint96 slot1 = uint96(0).createIndex(uint32(1));
        uint96 slot2 = uint96(0).createIndex(uint32(2));

        assertEq(delegator.getUnallocated(0), 0);
        assertEq(delegator.getAllocated(slot1), 100);
        assertEq(delegator.getAllocated(slot2), 0);
    }

    function test_slotAllocation_respectsOrderAndLimits() public {
        _deposit(alice, 100);

        delegator.createSlot(0, false, 30);
        delegator.createSlot(0, false, 50);

        uint96 slot1 = uint96(0).createIndex(uint32(1));
        uint96 slot2 = uint96(0).createIndex(uint32(2));

        assertEq(delegator.getUnallocated(0), 20);
        assertEq(delegator.getAllocated(slot1), 30);
        assertEq(delegator.getAllocated(slot2), 50);
    }

    function test_increaseLimit_consumesUnallocated_andUpdatesPrevSums() public {
        _deposit(alice, 100);

        delegator.createSlot(0, false, 30);
        delegator.createSlot(0, false, 50);

        uint96 slot1 = uint96(0).createIndex(uint32(1));
        uint96 slot2 = uint96(0).createIndex(uint32(2));

        vm.warp(1);
        delegator.setSize(slot1, 45);

        assertEq(delegator.getAllocatedAt(slot1, 1, ""), 45);
        assertEq(delegator.getAllocatedAt(slot2, 1, ""), 50);
        assertEq(delegator.getUnallocated(0), 5);
    }

    function test_increaseLimit_revertsWhenFullyAllocatedNonLast_withoutUnallocated() public {
        _deposit(alice, 100);

        delegator.createSlot(0, false, 60);
        delegator.createSlot(0, false, 60);

        uint96 slot1 = uint96(0).createIndex(uint32(1));

        vm.expectRevert(IUniversalDelegator.NotEnoughAvailable.selector);
        delegator.setSize(slot1, 80);
    }

    function test_increaseLimit_allowsWhenNotFullyAllocated_evenIfNotLastChild() public {
        _deposit(alice, 100);

        delegator.createSlot(0, false, 60);
        delegator.createSlot(0, false, 60);
        delegator.createSlot(0, false, 60);

        uint96 slot2 = uint96(0).createIndex(uint32(2));
        uint96 slot3 = uint96(0).createIndex(uint32(3));

        delegator.setSize(slot2, 80);

        assertEq(delegator.getAllocated(slot2), 40);
        assertEq(delegator.getAllocated(slot3), 0);
        assertEq(delegator.getUnallocated(0), 0);
    }

    function test_increaseLimit_allowsLastChild_withoutUnallocated() public {
        _deposit(alice, 100);

        delegator.createSlot(0, false, 30);
        delegator.createSlot(0, false, 30);

        uint96 slot1 = uint96(0).createIndex(uint32(1));
        uint96 slot2 = uint96(0).createIndex(uint32(2));

        delegator.setSize(slot2, 90);

        assertEq(delegator.getAllocated(slot1), 30);
        assertEq(delegator.getAllocated(slot2), 70);
        assertEq(delegator.getUnallocated(0), 0);
    }

    function test_decreaseLimit_schedulesPendingFree_untilDelayExpires() public {
        _deposit(alice, 100);

        delegator.createSlot(0, false, 60);
        delegator.createSlot(0, false, 30);

        uint96 slot1 = uint96(0).createIndex(uint32(1));
        uint96 slot2 = uint96(0).createIndex(uint32(2));

        vm.warp(1);
        delegator.setSize(slot1, 40);

        vm.warp(2);
        assertEq(delegator.getAvailable(0), 80);
        assertEq(delegator.getAllocated(slot1), 40);
        assertEq(delegator.getAllocated(slot2), 30);
        assertEq(delegator.getUnallocated(0), 10);

        vm.warp(4);
        assertEq(delegator.getAvailable(0), 100);
        assertEq(delegator.getAllocated(slot1), 40);
        assertEq(delegator.getAllocated(slot2), 30);
        assertEq(delegator.getUnallocated(0), 30);
    }

    function test_pendingFree_respectsAllocationWhenResizingChildren() public {
        _deposit(alice, 555);

        delegator.createSlot(0, false, 555);
        uint96 group = uint96(0).createIndex(uint32(1));

        delegator.createSlot(group, false, 444);
        uint96 networkSlot = group.createIndex(uint32(1));

        delegator.createSlot(networkSlot, false, 444);
        uint96 operatorSlot = networkSlot.createIndex(uint32(1));

        assertEq(delegator.getAllocated(group), 555);
        assertEq(delegator.getAllocated(networkSlot), 444);
        assertEq(delegator.getAllocated(operatorSlot), 444);

        vm.warp(1);
        delegator.setSize(networkSlot, 222);

        assertEq(delegator.getAvailable(group), 333);
        assertEq(delegator.getAllocated(networkSlot), 222);
        assertEq(delegator.getAllocated(operatorSlot), 222);

        vm.warp(2);
        delegator.setSize(operatorSlot, 222);

        assertEq(delegator.getAvailable(networkSlot), 222);
        assertEq(delegator.getAllocated(operatorSlot), 222);

        uint256 groupPending = delegator.getBalance(group) - delegator.getAvailable(group);
        uint256 networkPending = delegator.getBalance(networkSlot) - delegator.getAvailable(networkSlot);
        uint256 operatorPending = delegator.getBalance(operatorSlot) - delegator.getAvailable(operatorSlot);

        assertEq(groupPending, 222);
        assertEq(networkPending, 0);
        assertEq(operatorPending, 0);
    }

    function test_pendingFree_accumulatesOnRepeatedOperatorDecrease() public {
        _deposit(alice, 555);

        delegator.createSlot(0, false, 555);
        uint96 group = uint96(0).createIndex(uint32(1));

        delegator.createSlot(group, false, 444);
        uint96 networkSlot = group.createIndex(uint32(1));

        delegator.createSlot(networkSlot, false, 444);
        uint96 operatorSlot = networkSlot.createIndex(uint32(1));

        vm.warp(1);
        delegator.setSize(operatorSlot, 222);

        uint256 pendingAfterFirst = delegator.getBalance(networkSlot) - delegator.getAvailable(networkSlot);
        assertEq(pendingAfterFirst, 222);
        assertEq(delegator.getAllocated(operatorSlot), 222);

        vm.warp(2);
        delegator.setSize(operatorSlot, 0);

        uint256 pendingAfterSecond = delegator.getBalance(networkSlot) - delegator.getAvailable(networkSlot);
        assertEq(pendingAfterSecond, 444);
        assertEq(delegator.getAllocated(networkSlot), 444);
        assertEq(delegator.getAllocated(operatorSlot), 0);

        uint256 groupPending = delegator.getBalance(group) - delegator.getAvailable(group);
        assertEq(groupPending, 0);
    }

    function test_sharedGroup_allowsNetworkRestaking_betweenDepth2Siblings() public {
        _deposit(alice, 100);

        delegator.createSlot(0, true, 100);
        uint96 group = uint96(0).createIndex(uint32(1));

        delegator.createSlot(group, false, 80);
        delegator.createSlot(group, false, 80);
        uint96 net1 = group.createIndex(uint32(1));
        uint96 net2 = group.createIndex(uint32(2));

        assertEq(delegator.getAllocated(group), 100);
        assertEq(delegator.getAllocated(net1), 80);
        assertEq(delegator.getAllocated(net2), 80);
    }

    function test_depth3Operators_areIsolatedWithinNetwork() public {
        _deposit(alice, 100);

        delegator.createSlot(0, true, 100);
        uint96 group = uint96(0).createIndex(uint32(1));

        delegator.createSlot(group, false, 80);
        uint96 net1 = group.createIndex(uint32(1));

        delegator.createSlot(net1, false, 50);
        delegator.createSlot(net1, false, 50);
        uint96 op1 = net1.createIndex(uint32(1));
        uint96 op2 = net1.createIndex(uint32(2));

        assertEq(delegator.getAllocated(net1), 80);
        assertEq(delegator.getAllocated(op1), 50);
        assertEq(delegator.getAllocated(op2), 30);
    }

    function test_isRestaked_trueWhenGroupIsShared() public {
        bytes32 subnetwork = bytes32(uint256(1));

        _deposit(alice, 100);

        delegator.createSlot(0, true, 100);
        uint96 group = uint96(0).createIndex(uint32(1));

        delegator.createSlot(group, false, 100);
        uint96 networkSlot = group.createIndex(uint32(1));
        delegator.assignNetwork(networkSlot, subnetwork);

        delegator.createSlot(networkSlot, false, 100);
        uint96 operatorSlot = networkSlot.createIndex(uint32(1));
        delegator.assignOperator(operatorSlot, alice);

        assertTrue(delegator.isRestaked(subnetwork, alice));
        assertTrue(delegator.isRestakedAt(subnetwork, alice, uint48(block.timestamp), ""));
    }

    function test_isRestaked_falseWhenGroupNotShared() public {
        bytes32 subnetwork = bytes32(uint256(1));

        _deposit(alice, 100);

        delegator.createSlot(0, false, 100);
        uint96 group = uint96(0).createIndex(uint32(1));

        delegator.createSlot(group, false, 100);
        uint96 networkSlot = group.createIndex(uint32(1));
        delegator.assignNetwork(networkSlot, subnetwork);

        delegator.createSlot(networkSlot, false, 100);
        uint96 operatorSlot = networkSlot.createIndex(uint32(1));
        delegator.assignOperator(operatorSlot, alice);

        assertFalse(delegator.isRestaked(subnetwork, alice));
        assertFalse(delegator.isRestakedAt(subnetwork, alice, uint48(block.timestamp), ""));
    }

    function test_onlyCuratorRole_enforced() public {
        vm.startPrank(bob);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, bob, delegator.CURATOR_ROLE()
            )
        );
        delegator.createSlot(0, false, 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, bob, delegator.CURATOR_ROLE()
            )
        );
        delegator.setIsShared(uint96(0).createIndex(uint32(1)), true);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, bob, delegator.CURATOR_ROLE()
            )
        );
        delegator.setSize(uint96(0).createIndex(uint32(1)), 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, bob, delegator.CURATOR_ROLE()
            )
        );
        delegator.swapSlots(uint96(0).createIndex(uint32(1)), uint96(0).createIndex(uint32(2)));

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, bob, delegator.CURATOR_ROLE()
            )
        );
        delegator.assignNetwork(uint96(0).createIndex(uint32(1)), bytes32(uint256(1)));

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, bob, delegator.CURATOR_ROLE()
            )
        );
        delegator.unassignNetwork(bytes32(uint256(1)));

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, bob, delegator.CURATOR_ROLE()
            )
        );
        delegator.assignOperator(uint96(0).createIndex(uint32(1)), bob);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, bob, delegator.CURATOR_ROLE()
            )
        );
        delegator.unassignOperator(uint96(0).createIndex(uint32(1)), bob);

        vm.stopPrank();
    }

    function test_depthGuards_enforced() public {
        delegator.createSlot(0, false, 100);
        uint96 group = uint96(0).createIndex(uint32(1));

        delegator.createSlot(group, false, 100);
        uint96 networkSlot = group.createIndex(uint32(1));

        delegator.createSlot(networkSlot, false, 100);
        uint96 operatorSlot = networkSlot.createIndex(uint32(1));

        vm.expectRevert(IUniversalDelegator.WrongDepth.selector);
        delegator.setIsShared(0, true);

        vm.expectRevert(IUniversalDelegator.WrongDepth.selector);
        delegator.setIsShared(networkSlot, true);

        vm.expectRevert(IUniversalDelegator.WrongDepth.selector);
        delegator.setIsShared(operatorSlot, true);

        vm.expectRevert(IUniversalDelegator.WrongDepth.selector);
        delegator.assignNetwork(group, bytes32(uint256(1)));

        vm.expectRevert(IUniversalDelegator.WrongDepth.selector);
        delegator.assignOperator(networkSlot, alice);

        vm.expectRevert(IUniversalDelegator.WrongDepth.selector);
        delegator.createSlot(group, true, 1);
    }

    function test_networkAssignment_duplicateAndUnassignChecks() public {
        bytes32 subnetwork = bytes32(uint256(1));

        vm.expectRevert(IUniversalDelegator.NetworkNotAssigned.selector);
        delegator.unassignNetwork(subnetwork);

        _deposit(alice, 100);

        delegator.createSlot(0, false, 100);
        uint96 group = uint96(0).createIndex(uint32(1));

        delegator.createSlot(group, false, 100);
        delegator.createSlot(group, false, 100);
        uint96 net1 = group.createIndex(uint32(1));
        uint96 net2 = group.createIndex(uint32(2));

        delegator.assignNetwork(net1, subnetwork);

        vm.expectRevert(IUniversalDelegator.NetworkAlreadyAssigned.selector);
        delegator.assignNetwork(net2, subnetwork);

        vm.expectRevert(IUniversalDelegator.SlotAllocated.selector);
        delegator.unassignNetwork(subnetwork);

        _withdraw(alice, 100);
        delegator.unassignNetwork(subnetwork);
        assertEq(delegator.slotByNetwork(subnetwork), 0);
    }

    function test_operatorAssignment_duplicateAndUnassignChecks() public {
        _deposit(alice, 100);

        delegator.createSlot(0, false, 100);
        uint96 group = uint96(0).createIndex(uint32(1));

        delegator.createSlot(group, false, 100);
        uint96 networkSlot = group.createIndex(uint32(1));

        delegator.createSlot(networkSlot, false, 60);
        delegator.createSlot(networkSlot, false, 60);
        uint96 operatorSlot1 = networkSlot.createIndex(uint32(1));
        uint96 operatorSlot2 = networkSlot.createIndex(uint32(2));

        vm.expectRevert(IUniversalDelegator.OperatorNotAssigned.selector);
        delegator.unassignOperator(networkSlot, alice);

        delegator.assignOperator(operatorSlot1, alice);

        vm.expectRevert(IUniversalDelegator.OperatorAlreadyAssigned.selector);
        delegator.assignOperator(operatorSlot2, alice);

        vm.expectRevert(IUniversalDelegator.SlotAllocated.selector);
        delegator.unassignOperator(networkSlot, alice);

        _withdraw(alice, 100);
        delegator.unassignOperator(networkSlot, alice);
        assertEq(delegator.slotByOperator(networkSlot, alice), 0);
    }

    function test_setIsShared_revertsWhenAllocated() public {
        _deposit(alice, 1);

        delegator.createSlot(0, false, 1);
        uint96 group = uint96(0).createIndex(uint32(1));

        vm.expectRevert(IUniversalDelegator.SlotAllocated.selector);
        delegator.setIsShared(group, true);
    }

    function test_setIsShared_togglesNetworkRestaking() public {
        delegator.createSlot(0, false, 100);
        uint96 group = uint96(0).createIndex(uint32(1));

        delegator.createSlot(group, false, 80);
        delegator.createSlot(group, false, 80);
        uint96 net1 = group.createIndex(uint32(1));
        uint96 net2 = group.createIndex(uint32(2));

        _deposit(alice, 100);
        assertEq(delegator.getAllocated(net1), 80);
        assertEq(delegator.getAllocated(net2), 20);

        _withdraw(alice, 100);

        delegator.setIsShared(group, true);

        _deposit(alice, 100);
        assertEq(delegator.getAllocated(net1), 80);
        assertEq(delegator.getAllocated(net2), 80);
    }

    function test_swapSlots_changesAllocationAfterStakeDecrease() public {
        _deposit(alice, 100);

        delegator.createSlot(0, false, 30);
        delegator.createSlot(0, false, 50);

        uint96 slot1 = uint96(0).createIndex(uint32(1));
        uint96 slot2 = uint96(0).createIndex(uint32(2));

        vm.warp(1);
        delegator.swapSlots(slot1, slot2);

        vm.warp(2);
        _withdraw(alice, 60);

        assertEq(delegator.getAllocated(slot2), 40);
        assertEq(delegator.getAllocated(slot1), 0);
    }

    function test_swapSlots_revertsWrongOrder() public {
        _deposit(alice, 100);

        delegator.createSlot(0, false, 10);
        delegator.createSlot(0, false, 10);
        uint96 slot1 = uint96(0).createIndex(uint32(1));
        uint96 slot2 = uint96(0).createIndex(uint32(2));

        vm.expectRevert(IUniversalDelegator.WrongOrder.selector);
        delegator.swapSlots(slot2, slot1);
    }

    function test_swapSlots_revertsNotSameParent() public {
        _deposit(alice, 100);

        delegator.createSlot(0, false, 10);
        uint96 rootSlot = uint96(0).createIndex(uint32(1));

        delegator.createSlot(0, false, 10);
        uint96 group = uint96(0).createIndex(uint32(2));
        delegator.createSlot(group, false, 10);
        uint96 networkSlot = group.createIndex(uint32(1));

        vm.expectRevert(IUniversalDelegator.NotSameParent.selector);
        delegator.swapSlots(rootSlot, networkSlot);
    }

    function test_swapSlots_revertsNotSameAllocated() public {
        _deposit(alice, 3);

        delegator.createSlot(0, false, 5);
        delegator.createSlot(0, false, 5);
        uint96 slot1 = uint96(0).createIndex(uint32(1));
        uint96 slot2 = uint96(0).createIndex(uint32(2));

        vm.expectRevert(IUniversalDelegator.NotSameAllocated.selector);
        delegator.swapSlots(slot1, slot2);
    }

    function test_swapSlots_revertsPartiallyAllocated() public {
        _deposit(alice, 70);

        delegator.createSlot(0, false, 50);
        delegator.createSlot(0, false, 50);
        uint96 slot1 = uint96(0).createIndex(uint32(1));
        uint96 slot2 = uint96(0).createIndex(uint32(2));

        vm.expectRevert(IUniversalDelegator.PartiallyAllocated.selector);
        delegator.swapSlots(slot1, slot2);
    }

    function test_getAvailableAt_doesNotUnderflowForSmallTimestamps() public {
        _deposit(alice, 100);

        delegator.createSlot(0, false, 60);
        uint96 slot1 = uint96(0).createIndex(uint32(1));

        vm.warp(1);
        delegator.setSize(slot1, 40);

        assertEq(delegator.getAvailableAt(0, 2, ""), 80);
        assertEq(delegator.getAvailableAt(0, 4, ""), 100);
    }

    function _deposit(address user, uint256 amount) internal {
        collateral.transfer(user, amount);

        vm.startPrank(user);
        collateral.approve(address(vault), amount);
        vault.deposit(user, amount);
        vm.stopPrank();
    }

    function _withdraw(address user, uint256 amount) internal {
        vm.startPrank(user);
        vault.withdraw(user, amount);
        vm.stopPrank();
    }
}
