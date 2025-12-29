// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {VaultFactory} from "../../src/contracts/VaultFactory.sol";
import {DelegatorFactory} from "../../src/contracts/DelegatorFactory.sol";
import {SlasherFactory} from "../../src/contracts/SlasherFactory.sol";
import {NetworkRegistry} from "../../src/contracts/NetworkRegistry.sol";
import {OperatorRegistry} from "../../src/contracts/OperatorRegistry.sol";
import {VaultConfigurator} from "../../src/contracts/VaultConfigurator.sol";
import {NetworkMiddlewareService} from "../../src/contracts/service/NetworkMiddlewareService.sol";
import {OptInService} from "../../src/contracts/service/OptInService.sol";

import {Vault} from "../../src/contracts/vault/Vault.sol";
import {UniversalDelegator} from "../../src/contracts/delegator/UniversalDelegator.sol";
import {Slasher} from "../../src/contracts/slasher/Slasher.sol";

import {UniversalDelegatorIndex} from "../../src/contracts/libraries/UniversalDelegatorIndex.sol";
import {Subnetwork} from "../../src/contracts/libraries/Subnetwork.sol";

import {IBaseDelegator} from "../../src/interfaces/delegator/IBaseDelegator.sol";
import {IUniversalDelegator} from "../../src/interfaces/delegator/IUniversalDelegator.sol";
import {ISlasher} from "../../src/interfaces/slasher/ISlasher.sol";
import {IBaseSlasher} from "../../src/interfaces/slasher/IBaseSlasher.sol";
import {IVault} from "../../src/interfaces/vault/IVault.sol";
import {IVaultConfigurator} from "../../src/interfaces/IVaultConfigurator.sol";

import {Token} from "../mocks/Token.sol";

contract UniversalDelegatorTest is Test {
    using UniversalDelegatorIndex for uint96;
    using Subnetwork for address;

    uint48 internal constant EPOCH_DURATION = 3;
    uint256 internal constant MAX_AMOUNT = 1_000_000 ether;

    address internal owner;
    address internal alice;
    address internal bob;

    VaultFactory internal vaultFactory;
    DelegatorFactory internal delegatorFactory;
    SlasherFactory internal slasherFactory;
    NetworkRegistry internal networkRegistry;
    OperatorRegistry internal operatorRegistry;
    NetworkMiddlewareService internal networkMiddlewareService;
    OptInService internal operatorVaultOptInService;
    OptInService internal operatorNetworkOptInService;
    VaultConfigurator internal vaultConfigurator;

    Token internal collateral;
    Vault internal vault;
    UniversalDelegator internal delegator;
    Slasher internal slasher;

    function setUp() public {
        vm.warp(0);

        owner = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        vaultFactory = new VaultFactory(owner);
        delegatorFactory = new DelegatorFactory(owner);
        slasherFactory = new SlasherFactory(owner);
        networkRegistry = new NetworkRegistry();
        operatorRegistry = new OperatorRegistry();
        networkMiddlewareService = new NetworkMiddlewareService(address(networkRegistry));
        operatorVaultOptInService =
            new OptInService(address(operatorRegistry), address(vaultFactory), "OperatorVaultOptInService");
        operatorNetworkOptInService =
            new OptInService(address(operatorRegistry), address(networkRegistry), "OperatorNetworkOptInService");

        address vaultImpl =
            address(new Vault(address(delegatorFactory), address(slasherFactory), address(vaultFactory)));
        vaultFactory.whitelist(vaultImpl);

        address delegatorImpl = address(
            new UniversalDelegator(
                address(networkRegistry),
                address(vaultFactory),
                address(operatorVaultOptInService),
                address(operatorNetworkOptInService),
                address(delegatorFactory),
                delegatorFactory.totalTypes()
            )
        );
        delegatorFactory.whitelist(delegatorImpl);

        address slasherImpl = address(
            new Slasher(
                address(vaultFactory),
                address(networkMiddlewareService),
                address(slasherFactory),
                slasherFactory.totalTypes()
            )
        );
        slasherFactory.whitelist(slasherImpl);

        collateral = new Token("Token");
        vaultConfigurator =
            new VaultConfigurator(address(vaultFactory), address(delegatorFactory), address(slasherFactory));

        (address vault_, address delegator_, address slasher_) = vaultConfigurator.create(
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
                withSlasher: true,
                slasherIndex: 0,
                slasherParams: abi.encode(
                    ISlasher.InitParams({baseParams: IBaseSlasher.BaseParams({isBurnerHook: false})})
                )
            })
        );

        vault = Vault(vault_);
        delegator = UniversalDelegator(delegator_);
        slasher = Slasher(slasher_);
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

    function test_isolatedGroups_prioritizedOverTime() public {
        delegator.createSlot(0, false, 30);
        delegator.createSlot(0, false, 50);
        delegator.createSlot(0, false, 100);

        uint96 slot1 = uint96(0).createIndex(uint32(1));
        uint96 slot2 = uint96(0).createIndex(uint32(2));
        uint96 slot3 = uint96(0).createIndex(uint32(3));

        vm.warp(1);
        _deposit(alice, 60);

        assertEq(delegator.getAllocatedAt(slot1, 1, ""), 30);
        assertEq(delegator.getAllocatedAt(slot2, 1, ""), 30);
        assertEq(delegator.getAllocatedAt(slot3, 1, ""), 0);

        vm.warp(2);
        _deposit(alice, 60);

        assertEq(delegator.getAllocatedAt(slot1, 2, ""), 30);
        assertEq(delegator.getAllocatedAt(slot2, 2, ""), 50);
        assertEq(delegator.getAllocatedAt(slot3, 2, ""), 40);
    }

    function test_isolatedNetworks_followGroupPriority() public {
        _deposit(alice, 150);

        delegator.createSlot(0, false, 200);
        uint96 group = uint96(0).createIndex(uint32(1));

        delegator.createSlot(group, false, 60);
        delegator.createSlot(group, false, 120);
        uint96 net1 = group.createIndex(uint32(1));
        uint96 net2 = group.createIndex(uint32(2));

        assertEq(delegator.getAllocated(group), 150);
        assertEq(delegator.getAllocated(net1), 60);
        assertEq(delegator.getAllocated(net2), 90);
    }

    function test_isolatedOperators_prioritizedAfterStakeDecrease() public {
        delegator.createSlot(0, false, 1000);
        uint96 group = uint96(0).createIndex(uint32(1));

        delegator.createSlot(group, false, 1000);
        uint96 networkSlot = group.createIndex(uint32(1));

        delegator.createSlot(networkSlot, false, 70);
        delegator.createSlot(networkSlot, false, 70);
        uint96 op1 = networkSlot.createIndex(uint32(1));
        uint96 op2 = networkSlot.createIndex(uint32(2));

        vm.warp(1);
        _deposit(alice, 100);

        assertEq(delegator.getAllocated(op1), 70);
        assertEq(delegator.getAllocated(op2), 30);

        vm.warp(2);
        _withdraw(alice, 40);

        assertEq(delegator.getAllocated(op1), 60);
        assertEq(delegator.getAllocated(op2), 0);
    }

    function test_isolatedSlots_pendingFree_delaysReallocation() public {
        _deposit(alice, 100);

        delegator.createSlot(0, false, 70);
        delegator.createSlot(0, false, 70);
        uint96 slot1 = uint96(0).createIndex(uint32(1));
        uint96 slot2 = uint96(0).createIndex(uint32(2));

        assertEq(delegator.getAllocated(slot1), 70);
        assertEq(delegator.getAllocated(slot2), 30);

        vm.warp(1);
        delegator.setSize(slot1, 30);

        assertEq(delegator.getAvailable(0), 60);
        assertEq(delegator.getAllocated(slot1), 30);
        assertEq(delegator.getAllocated(slot2), 30);

        vm.warp(1 + EPOCH_DURATION);
        assertEq(delegator.getAvailable(0), 100);
        assertEq(delegator.getAllocated(slot1), 30);
        assertEq(delegator.getAllocated(slot2), 70);
    }

    function test_isolatedSlots_lateSizeIncrease_doesNotAffectEarlier() public {
        _deposit(alice, 90);

        delegator.createSlot(0, false, 50);
        delegator.createSlot(0, false, 60);
        uint96 slot1 = uint96(0).createIndex(uint32(1));
        uint96 slot2 = uint96(0).createIndex(uint32(2));

        assertEq(delegator.getAllocated(slot1), 50);
        assertEq(delegator.getAllocated(slot2), 40);

        vm.warp(1);
        delegator.setSize(slot2, 100);

        assertEq(delegator.getAllocated(slot1), 50);
        assertEq(delegator.getAllocated(slot2), 40);

        vm.warp(2);
        _deposit(alice, 30);

        assertEq(delegator.getAllocated(slot1), 50);
        assertEq(delegator.getAllocated(slot2), 70);
    }

    function test_sharedGroup_slashCappedAcrossNetworks_sameCaptureTimestamp() public {
        address network1 = makeAddr("network1");
        address network2 = makeAddr("network2");
        address network3 = makeAddr("network3");
        address middleware = makeAddr("middleware");
        address operator1 = alice;
        address operator2 = bob;
        address operator3 = makeAddr("charlie");

        _registerNetwork(network1, middleware);
        _registerNetwork(network2, middleware);
        _registerNetwork(network3, middleware);
        _registerOperator(operator1);
        _registerOperator(operator2);
        _registerOperator(operator3);
        _optIn(operator1, network1);
        _optIn(operator2, network2);
        _optIn(operator3, network3);

        bytes32 subnetwork1 = network1.subnetwork(0);
        bytes32 subnetwork2 = network2.subnetwork(0);
        bytes32 subnetwork3 = network3.subnetwork(0);

        delegator.createSlot(0, true, 60);
        delegator.createSlot(0, false, 40);
        uint96 group1 = uint96(0).createIndex(uint32(1));
        uint96 group2 = uint96(0).createIndex(uint32(2));

        delegator.createSlot(group1, false, 60);
        delegator.createSlot(group1, false, 60);
        uint96 netSlot1 = group1.createIndex(uint32(1));
        uint96 netSlot2 = group1.createIndex(uint32(2));
        delegator.assignNetwork(netSlot1, subnetwork1);
        delegator.assignNetwork(netSlot2, subnetwork2);

        delegator.createSlot(netSlot1, false, 60);
        uint96 opSlot1 = netSlot1.createIndex(uint32(1));
        delegator.assignOperator(opSlot1, operator1);

        delegator.createSlot(netSlot2, false, 60);
        uint96 opSlot2 = netSlot2.createIndex(uint32(1));
        delegator.assignOperator(opSlot2, operator2);

        delegator.createSlot(group2, false, 40);
        uint96 netSlot3 = group2.createIndex(uint32(1));
        delegator.assignNetwork(netSlot3, subnetwork3);

        delegator.createSlot(netSlot3, false, 40);
        uint96 opSlot3 = netSlot3.createIndex(uint32(1));
        delegator.assignOperator(opSlot3, operator3);

        vm.warp(18);
        _deposit(alice, 100);

        uint48 captureTimestamp = 18;
        vm.warp(20);

        vm.startPrank(middleware);
        assertEq(slasher.slash(subnetwork1, operator1, 60, captureTimestamp, ""), 60);
        vm.expectRevert();
        slasher.slash(subnetwork2, operator2, 60, captureTimestamp, "");
        assertEq(slasher.slash(subnetwork3, operator3, 40, captureTimestamp, ""), 40);
        vm.stopPrank();
    }

    function test_sharedGroup_slashCappedAcrossNetworks_differentCaptureTimestamp() public {
        address network1 = makeAddr("network1");
        address network2 = makeAddr("network2");
        address middleware = makeAddr("middleware");
        address operator1 = alice;
        address operator2 = bob;

        _registerNetwork(network1, middleware);
        _registerNetwork(network2, middleware);
        _registerOperator(operator1);
        _registerOperator(operator2);
        _optIn(operator1, network1);
        _optIn(operator2, network2);

        bytes32 subnetwork1 = network1.subnetwork(0);
        bytes32 subnetwork2 = network2.subnetwork(0);

        delegator.createSlot(0, true, 60);
        uint96 group = uint96(0).createIndex(uint32(1));

        delegator.createSlot(group, false, 60);
        delegator.createSlot(group, false, 60);
        uint96 netSlot1 = group.createIndex(uint32(1));
        uint96 netSlot2 = group.createIndex(uint32(2));
        delegator.assignNetwork(netSlot1, subnetwork1);
        delegator.assignNetwork(netSlot2, subnetwork2);

        delegator.createSlot(netSlot1, false, 60);
        uint96 opSlot1 = netSlot1.createIndex(uint32(1));
        delegator.assignOperator(opSlot1, operator1);

        delegator.createSlot(netSlot2, false, 60);
        uint96 opSlot2 = netSlot2.createIndex(uint32(1));
        delegator.assignOperator(opSlot2, operator2);

        vm.warp(1);
        _deposit(alice, 60);

        vm.warp(5);

        vm.startPrank(middleware);
        assertEq(slasher.slash(subnetwork1, operator1, 60, 3, ""), 60);
        vm.expectRevert();
        slasher.slash(subnetwork2, operator2, 60, 4, "");
        vm.stopPrank();
    }

    function test_sharedGroup_slashAllowsNewStake_laterCaptureTimestamp() public {
        address network1 = makeAddr("network1");
        address network2 = makeAddr("network2");
        address middleware = makeAddr("middleware");
        address operator1 = alice;
        address operator2 = bob;

        _registerNetwork(network1, middleware);
        _registerNetwork(network2, middleware);
        _registerOperator(operator1);
        _registerOperator(operator2);
        _optIn(operator1, network1);
        _optIn(operator2, network2);

        bytes32 subnetwork1 = network1.subnetwork(0);
        bytes32 subnetwork2 = network2.subnetwork(0);

        delegator.createSlot(0, true, 200);
        uint96 group = uint96(0).createIndex(uint32(1));

        delegator.createSlot(group, false, 200);
        delegator.createSlot(group, false, 200);
        uint96 netSlot1 = group.createIndex(uint32(1));
        uint96 netSlot2 = group.createIndex(uint32(2));
        delegator.assignNetwork(netSlot1, subnetwork1);
        delegator.assignNetwork(netSlot2, subnetwork2);

        delegator.createSlot(netSlot1, false, 200);
        uint96 opSlot1 = netSlot1.createIndex(uint32(1));
        delegator.assignOperator(opSlot1, operator1);

        delegator.createSlot(netSlot2, false, 200);
        uint96 opSlot2 = netSlot2.createIndex(uint32(1));
        delegator.assignOperator(opSlot2, operator2);

        vm.warp(1);
        _deposit(alice, 100);

        vm.warp(4);
        vm.startPrank(middleware);
        assertEq(slasher.slash(subnetwork1, operator1, 60, 2, ""), 60);
        vm.expectRevert();
        slasher.slash(subnetwork2, operator2, 60, 2, "");
        vm.stopPrank();

        vm.warp(6);
        _deposit(alice, 80);

        vm.warp(8);
        vm.startPrank(middleware);
        assertEq(slasher.slash(subnetwork2, operator2, 60, 6, ""), 60);
        vm.stopPrank();
    }

    function testFuzz_isolatedGroups_followPriority(uint256 depositAmount, uint256 size1, uint256 size2) public {
        uint256 amount = bound(depositAmount, 1, MAX_AMOUNT);
        uint256 cap1 = bound(size1, 0, MAX_AMOUNT);
        uint256 cap2 = bound(size2, 0, MAX_AMOUNT);

        delegator.createSlot(0, false, cap1);
        delegator.createSlot(0, false, cap2);
        uint96 slot1 = uint96(0).createIndex(uint32(1));
        uint96 slot2 = uint96(0).createIndex(uint32(2));

        _deposit(alice, amount);

        uint256 expected1 = amount < cap1 ? amount : cap1;
        uint256 remaining = amount > expected1 ? amount - expected1 : 0;
        uint256 expected2 = remaining < cap2 ? remaining : cap2;

        assertEq(delegator.getAllocated(slot1), expected1);
        assertEq(delegator.getAllocated(slot2), expected2);
        assertLe(delegator.getAllocated(slot1) + delegator.getAllocated(slot2), delegator.getAvailable(0));
    }

    function testFuzz_isolatedOperators_followPriority(uint256 depositAmount, uint256 size1, uint256 size2) public {
        uint256 amount = bound(depositAmount, 1, MAX_AMOUNT);
        uint256 cap1 = bound(size1, 0, MAX_AMOUNT);
        uint256 cap2 = bound(size2, 0, MAX_AMOUNT);

        delegator.createSlot(0, false, MAX_AMOUNT);
        uint96 group = uint96(0).createIndex(uint32(1));

        delegator.createSlot(group, false, MAX_AMOUNT);
        uint96 networkSlot = group.createIndex(uint32(1));

        delegator.createSlot(networkSlot, false, cap1);
        delegator.createSlot(networkSlot, false, cap2);
        uint96 op1 = networkSlot.createIndex(uint32(1));
        uint96 op2 = networkSlot.createIndex(uint32(2));

        _deposit(alice, amount);

        uint256 expected1 = amount < cap1 ? amount : cap1;
        uint256 remaining = amount > expected1 ? amount - expected1 : 0;
        uint256 expected2 = remaining < cap2 ? remaining : cap2;

        assertEq(delegator.getAllocated(op1), expected1);
        assertEq(delegator.getAllocated(op2), expected2);
    }

    function testFuzz_isolatedSlots_depositWithdraw_overTime(
        uint256 depositAmount,
        uint256 withdrawAmount,
        uint256 size1,
        uint256 size2
    ) public {
        uint256 amount = bound(depositAmount, 1, MAX_AMOUNT);
        uint256 cap1 = bound(size1, 0, MAX_AMOUNT);
        uint256 cap2 = bound(size2, 0, MAX_AMOUNT);

        delegator.createSlot(0, false, cap1);
        delegator.createSlot(0, false, cap2);
        uint96 slot1 = uint96(0).createIndex(uint32(1));
        uint96 slot2 = uint96(0).createIndex(uint32(2));

        vm.warp(1);
        _deposit(alice, amount);

        uint256 withdraw = bound(withdrawAmount, 0, amount);
        vm.warp(2);
        if (withdraw > 0) {
            _withdraw(alice, withdraw);
        }

        uint256 remaining = amount - withdraw;
        uint256 expected1 = remaining < cap1 ? remaining : cap1;
        uint256 afterFirst = remaining > expected1 ? remaining - expected1 : 0;
        uint256 expected2 = afterFirst < cap2 ? afterFirst : cap2;

        assertEq(delegator.getAllocated(slot1), expected1);
        assertEq(delegator.getAllocated(slot2), expected2);
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
        assertEq(delegator.slotOfNetwork(subnetwork), 0);
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
        assertEq(delegator.slotOfOperator(networkSlot, alice), 0);
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

    function _registerOperator(address operator) internal {
        vm.startPrank(operator);
        operatorRegistry.registerOperator();
        vm.stopPrank();
    }

    function _registerNetwork(address network, address middleware) internal {
        vm.startPrank(network);
        networkRegistry.registerNetwork();
        networkMiddlewareService.setMiddleware(middleware);
        vm.stopPrank();
    }

    function _optIn(address operator, address network) internal {
        vm.startPrank(operator);
        operatorVaultOptInService.optIn(address(vault));
        operatorNetworkOptInService.optIn(network);
        vm.stopPrank();
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
