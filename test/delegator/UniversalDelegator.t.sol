// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

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

import {VaultV2} from "../../src/contracts/vault/VaultV2.sol";
import {Vault as VaultV1} from "../../src/contracts/vault/Vault.sol";
import {VaultTokenized} from "../../src/contracts/vault/VaultTokenized.sol";
import {FullRestakeDelegator} from "../../src/contracts/delegator/FullRestakeDelegator.sol";
import {NetworkRestakeDelegator} from "../../src/contracts/delegator/NetworkRestakeDelegator.sol";
import {OperatorNetworkSpecificDelegator} from "../../src/contracts/delegator/OperatorNetworkSpecificDelegator.sol";
import {OperatorSpecificDelegator} from "../../src/contracts/delegator/OperatorSpecificDelegator.sol";
import {UniversalDelegator} from "../../src/contracts/delegator/UniversalDelegator.sol";
import {Slasher} from "../../src/contracts/slasher/Slasher.sol";
import {UniversalSlasher} from "../../src/contracts/slasher/UniversalSlasher.sol";
import {VetoSlasher} from "../../src/contracts/slasher/VetoSlasher.sol";

import {Checkpoints} from "../../src/contracts/libraries/CheckpointsV2.sol";
import {UniversalDelegatorIndex} from "../../src/contracts/libraries/UniversalDelegatorIndex.sol";
import {Subnetwork} from "../../src/contracts/libraries/Subnetwork.sol";

import {IBaseDelegator} from "../../src/interfaces/delegator/IBaseDelegator.sol";
import {IFullRestakeDelegator} from "../../src/interfaces/delegator/IFullRestakeDelegator.sol";
import {INetworkRestakeDelegator} from "../../src/interfaces/delegator/INetworkRestakeDelegator.sol";
import {IOperatorNetworkSpecificDelegator} from "../../src/interfaces/delegator/IOperatorNetworkSpecificDelegator.sol";
import {IOperatorSpecificDelegator} from "../../src/interfaces/delegator/IOperatorSpecificDelegator.sol";
import {
    IUniversalDelegator,
    CREATE_SLOT_ROLE,
    HOOK_GAS_LIMIT,
    HOOK_RESERVE,
    HOOK_SET_ROLE,
    MAX_GROUPS,
    MAX_NETWORKS,
    MAX_OPERATORS,
    SET_SIZE_ROLE,
    SWAP_SLOTS_ROLE,
    REMOVE_SLOT_ROLE
} from "../../src/interfaces/delegator/IUniversalDelegator.sol";
import {IDelegatorHook} from "../../src/interfaces/delegator/IDelegatorHookV2.sol";
import {IBaseSlasher} from "../../src/interfaces/slasher/IBaseSlasher.sol";
import {ISlasher} from "../../src/interfaces/slasher/ISlasher.sol";
import {IUniversalSlasher} from "../../src/interfaces/slasher/IUniversalSlasher.sol";
import {IEntity} from "../../src/interfaces/common/IEntity.sol";
import {IMigratableEntity} from "../../src/interfaces/common/IMigratableEntity.sol";
import {IVault} from "../../src/interfaces/vault/IVault.sol";
import {IVaultV2} from "../../src/interfaces/vault/IVaultV2.sol";
import {IVaultConfigurator} from "../../src/interfaces/IVaultConfigurator.sol";

import {Token} from "../mocks/Token.sol";
import {MockRewards} from "../mocks/MockRewards.sol";

contract UniversalDelegatorHookMock is IDelegatorHook {
    bytes32 public lastSubnetwork;
    address public lastOperator;
    uint256 public lastAmount;
    bytes public lastData;
    uint256 public calls;

    function onSlash(bytes32 subnetwork, address operator, uint256 amount, bytes calldata data) external {
        lastSubnetwork = subnetwork;
        lastOperator = operator;
        lastAmount = amount;
        lastData = data;
        ++calls;
    }
}

contract UniversalDelegatorCoverageHarness is UniversalDelegator {
    using Checkpoints for Checkpoints.Trace208;

    constructor() UniversalDelegator(address(0), address(0), address(0), 0, address(0)) {}

    function setSlotExistsRaw(uint96 index, bool exists_) external {
        slots[index].exists = exists_;
    }

    function setNeedPrevSumsSyncRaw(uint96 parentIndex, bool value) external {
        slots[parentIndex].needPrevSumsSync = value;
    }

    function needPrevSumsSyncRaw(uint96 parentIndex) external view returns (bool) {
        return slots[parentIndex].needPrevSumsSync;
    }

    function setParentChildrenRaw(uint96 parentIndex, uint32 firstChild, uint32 lastChild, uint32 numChildren)
        external
    {
        slots[parentIndex].firstChild = firstChild;
        slots[parentIndex].lastChild = lastChild;
        slots[parentIndex].numChildren = numChildren;
    }

    function setSlotLinksRaw(uint96 index, uint32 prevSlot, uint32 nextSlot) external {
        slots[index].prevSlot = prevSlot;
        slots[index].nextSlot = nextSlot;
    }

    function pushSizeRaw(uint96 index, uint48 key, uint208 size) external {
        slots[index].size.push(key, size);
    }

    function prevSumLatestRaw(uint96 index) external view returns (uint208) {
        return slots[index].prevSum.latest();
    }

    function exposeSlotExists(uint96 index) external slotExists(index) {}

    function exposeSyncPrevSums(uint96 parentIndex) external syncPrevSums(parentIndex) {}
}

contract UniversalDelegatorTest is Test {
    using UniversalDelegatorIndex for uint96;
    using Subnetwork for address;

    uint48 internal constant EPOCH_DURATION = 3;
    uint128 internal constant MAX_AMOUNT = 1_000_000 ether;
    string internal constant VAULT_NAME = "Test";
    string internal constant VAULT_SYMBOL = "TEST";
    address internal constant DUMMY_NETWORK = address(0xdeAD00000000000000000000000000000000dEAd);
    address internal constant DUMMY_OPERATOR_BASE = address(0xBEEF00000000000000000000000000000000BEEf);

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
    MockRewards internal rewards;

    Token internal collateral;
    IVaultV2 internal vault;
    UniversalDelegator internal delegator;
    IUniversalSlasher internal slasher;
    uint96 internal dummyNetworkId;
    uint160 internal dummyOperatorId;

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
        rewards = new MockRewards();

        address vaultImplV1 =
            address(new VaultV1(address(delegatorFactory), address(slasherFactory), address(vaultFactory)));
        vaultFactory.whitelist(vaultImplV1);

        address vaultImplTokenized =
            address(new VaultTokenized(address(delegatorFactory), address(slasherFactory), address(vaultFactory)));
        vaultFactory.whitelist(vaultImplTokenized);

        address vaultImpl = address(
            new VaultV2(address(delegatorFactory), address(slasherFactory), address(vaultFactory), address(rewards))
        );
        vaultFactory.whitelist(vaultImpl);

        address delegatorImpl = address(
            new UniversalDelegator(
                address(networkRegistry),
                address(vaultFactory),
                address(delegatorFactory),
                delegatorFactory.totalTypes(),
                address(networkMiddlewareService)
            )
        );
        delegatorFactory.whitelist(delegatorImpl);

        address slasherImpl = address(
            new UniversalSlasher(
                address(vaultFactory),
                address(networkMiddlewareService),
                address(networkRegistry),
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
                    IVaultV2.InitParams({
                        name: VAULT_NAME,
                        symbol: VAULT_SYMBOL,
                        collateral: address(collateral),
                        burner: address(0xdEaD),
                        epochDuration: EPOCH_DURATION,
                        depositWhitelist: false,
                        depositorsWhitelisted: new address[](0),
                        isDepositLimit: false,
                        depositLimit: 0,
                        defaultAdminRoleHolder: owner,
                        depositWhitelistSetRoleHolder: address(0),
                        depositorWhitelistRoleHolder: address(0),
                        isDepositLimitSetRoleHolder: address(0),
                        depositLimitSetRoleHolder: address(0),
                        setPluginLimitRoleHolder: address(0),
                        allocatePluginRoleHolder: address(0),
                        pluginsData: new IVaultV2.PluginData[](0)
                    })
                ),
                delegatorIndex: 0,
                delegatorParams: abi.encode(
                    IUniversalDelegator.InitParams({
                        defaultAdminRoleHolder: owner,
                        hook: address(0),
                        hookSetRoleHolder: address(0),
                        createSlotRoleHolder: owner,
                        setIsSharedRoleHolder: owner,
                        setSizeRoleHolder: owner,
                        setShareRoleHolder: owner,
                        swapSlotsRoleHolder: owner,
                        withdrawalBufferSize: type(uint128).max
                    })
                ),
                withSlasher: true,
                slasherIndex: 0,
                slasherParams: abi.encode(
                    IUniversalSlasher.InitParams({
                        isBurnerHook: false, vetoDuration: 1, resolverSetDelay: EPOCH_DURATION * 3
                    })
                )
            })
        );

        vault = IVaultV2(vault_);
        delegator = UniversalDelegator(delegator_);
        slasher = IUniversalSlasher(slasher_);
    }

    function test_checkpointTracksHistory_andDefaults() public {
        _createSlot(0, false, 30);
        uint96 slot1 = _rootIndex(uint32(1));

        assertEq(delegator.getAllocatedAt(slot1, 0, 0), 0);

        vm.warp(5);
        _deposit(alice, 100);
        assertEq(delegator.getAllocatedAt(slot1, 5, 0), 30);

        vm.warp(7);
        delegator.setSize(slot1, 20);
        assertEq(delegator.getAllocatedAt(slot1, 7, 0), 30);
        assertEq(delegator.getAllocatedAt(slot1, 9, EPOCH_DURATION), 20);
    }

    function test_createSlot_root_allowsDepth1() public {
        _createSlot(0, false, 10);
        uint96 slot1 = _rootIndex(uint32(1));

        assertEq(delegator.getAllocated(slot1, 0), 0);
    }

    function test_setSize_allowsNonZeroCurrentSize() public {
        _createSlot(0, false, 10);
        uint96 slot1 = _rootIndex(uint32(1));

        delegator.setSize(slot1, 20);
        assertEq(delegator.getAllocated(slot1, 0), 0);
    }

    function test_slotAllocation_partialFill() public {
        _deposit(alice, 100);

        _createSlot(0, false, 30);
        _createSlot(0, false, 500);

        uint96 slot1 = _rootIndex(uint32(1));
        uint96 slot2 = _rootIndex(uint32(2));

        assertEq(_unallocated2(0, slot1, slot2), 0);
        assertEq(delegator.getAllocated(slot1, 0), 30);
        assertEq(delegator.getAllocated(slot2, 0), 70);
    }

    function test_slotAllocation_partialFill_2() public {
        _deposit(alice, 100);

        _createSlot(0, false, 500);
        _createSlot(0, false, 30);

        uint96 slot1 = _rootIndex(uint32(1));
        uint96 slot2 = _rootIndex(uint32(2));

        assertEq(_unallocated2(0, slot1, slot2), 0);
        assertEq(delegator.getAllocated(slot1, 0), 100);
        assertEq(delegator.getAllocated(slot2, 0), 0);
    }

    function test_slotAllocation_respectsOrderAndLimits() public {
        _deposit(alice, 100);

        _createSlot(0, false, 30);
        _createSlot(0, false, 50);

        uint96 slot1 = _rootIndex(uint32(1));
        uint96 slot2 = _rootIndex(uint32(2));

        assertEq(_unallocated2(0, slot1, slot2), 20);
        assertEq(delegator.getAllocated(slot1, 0), 30);
        assertEq(delegator.getAllocated(slot2, 0), 50);
    }

    function test_increaseLimit_consumesUnallocated_andUpdatesPrevSums() public {
        _deposit(alice, 100);

        _createSlot(0, false, 30);
        _createSlot(0, false, 50);

        uint96 slot1 = _rootIndex(uint32(1));
        uint96 slot2 = _rootIndex(uint32(2));

        vm.warp(1);
        delegator.setSize(slot1, 45);

        assertEq(delegator.getAllocatedAt(slot1, 1, 0), 45);
        assertEq(delegator.getAllocatedAt(slot2, 1, 0), 50);
        assertEq(_unallocated2(0, slot1, slot2), 5);
    }

    function test_increaseLimit_revertsWhenFullyAllocatedNonLast_withoutUnallocated() public {
        _deposit(alice, 100);

        _createSlot(0, false, 60);
        _createSlot(0, false, 60);

        uint96 slot1 = _rootIndex(uint32(1));
        uint96 slot2 = _rootIndex(uint32(2));

        vm.expectRevert(IUniversalDelegator.NotEnoughAvailable.selector);
        delegator.setSize(slot1, 80);
    }

    function test_increaseLimit_allowsWhenNotFullyAllocated_evenIfNotLastChild() public {
        _deposit(alice, 100);

        _createSlot(0, false, 60);
        _createSlot(0, false, 60);
        _createSlot(0, false, 60);

        uint96 slot1 = _rootIndex(uint32(1));
        uint96 slot2 = _rootIndex(uint32(2));
        uint96 slot3 = _rootIndex(uint32(3));

        delegator.setSize(slot2, 80);

        assertEq(delegator.getAllocated(slot2, 0), 40);
        assertEq(delegator.getAllocated(slot3, 0), 0);
        assertEq(_unallocated3(0, slot1, slot2, slot3), 0);
    }

    function test_increaseLimit_allowsLastChild_withoutUnallocated() public {
        _deposit(alice, 100);

        _createSlot(0, false, 30);
        _createSlot(0, false, 30);

        uint96 slot1 = _rootIndex(uint32(1));
        uint96 slot2 = _rootIndex(uint32(2));

        delegator.setSize(slot2, 90);

        assertEq(delegator.getAllocated(slot1, 0), 30);
        assertEq(delegator.getAllocated(slot2, 0), 70);
        assertEq(_unallocated2(0, slot1, slot2), 0);
    }

    function test_decreaseLimit_schedulesPending_untilDelayExpires() public {
        _deposit(alice, 100);

        _createSlot(0, false, 60);
        _createSlot(0, false, 30);

        uint96 slot1 = _rootIndex(uint32(1));
        uint96 slot2 = _rootIndex(uint32(2));

        vm.warp(1);
        delegator.setSize(slot1, 40);

        vm.warp(2);
        assertEq(delegator.getAvailable(0, 0), 80);
        assertEq(delegator.getAllocated(slot1, 0), 60);
        assertEq(delegator.getAllocated(slot2, 0), 30);
        assertEq(_unallocated2(0, slot1, slot2), 0);

        vm.warp(4);
        assertEq(delegator.getAvailable(0, 0), 100);
        assertEq(delegator.getAllocated(slot1, 0), 40);
        assertEq(delegator.getAllocated(slot2, 0), 30);
        assertEq(_unallocated2(0, slot1, slot2), 30);
    }

    function test_childrenPending_respectsAllocationWhenResizingChildren() public {
        _deposit(alice, 555);

        _createSlot(0, false, 555);
        uint96 group = _rootIndex(uint32(1));

        _createSlot(group, false, 444);
        uint96 networkSlot = group.createIndex(uint32(1));

        _createSlot(networkSlot, false, 444);
        uint96 operatorSlot = networkSlot.createIndex(uint32(1));

        assertEq(delegator.getAllocated(group, 0), 555);
        assertEq(delegator.getAllocated(networkSlot, 0), 444);
        assertEq(delegator.getAllocated(operatorSlot, 0), 444);

        vm.warp(1);
        delegator.setSize(networkSlot, 222);

        assertEq(delegator.getAvailable(group, 0), 333);
        assertEq(delegator.getAllocated(networkSlot, 0), 444);
        assertEq(delegator.getAllocated(operatorSlot, 0), 444);

        vm.warp(2);
        delegator.setSize(operatorSlot, 222);

        assertEq(delegator.getAvailable(networkSlot, 0), 222);
        assertEq(delegator.getAllocated(operatorSlot, 0), 444);

        uint256 groupPending = delegator.getBalance(group, 0) - delegator.getAvailable(group, 0);
        uint256 networkPending = delegator.getBalance(networkSlot, 0) - delegator.getAvailable(networkSlot, 0);
        uint256 operatorPending = delegator.getBalance(operatorSlot, 0) - delegator.getAvailable(operatorSlot, 0);

        assertEq(groupPending, 222);
        assertEq(networkPending, 222);
        assertEq(operatorPending, 0);
    }

    function test_childrenPending_accumulatesOnRepeatedOperatorDecrease() public {
        _deposit(alice, 555);

        _createSlot(0, false, 555);
        uint96 group = _rootIndex(uint32(1));

        _createSlot(group, false, 444);
        uint96 networkSlot = group.createIndex(uint32(1));

        _createSlot(networkSlot, false, 444);
        uint96 operatorSlot = networkSlot.createIndex(uint32(1));

        vm.warp(1);
        delegator.setSize(operatorSlot, 222);

        uint256 pendingAfterFirst = delegator.getBalance(networkSlot, 0) - delegator.getAvailable(networkSlot, 0);
        assertEq(pendingAfterFirst, 222);
        assertEq(delegator.getAllocated(operatorSlot, 0), 444);

        vm.warp(2);
        delegator.setSize(operatorSlot, 0);

        uint256 pendingAfterSecond = delegator.getBalance(networkSlot, 0) - delegator.getAvailable(networkSlot, 0);
        assertEq(pendingAfterSecond, 444);
        assertEq(delegator.getAllocated(networkSlot, 0), 444);
        assertEq(delegator.getAllocated(operatorSlot, 0), 444);

        uint256 groupPending = delegator.getBalance(group, 0) - delegator.getAvailable(group, 0);
        assertEq(groupPending, 0);
    }

    function test_getAvailableAt_pendingHints_matchNoHintPath() public {
        _deposit(alice, 555);

        _createSlot(0, false, 555);
        uint96 group = _rootIndex(uint32(1));

        bytes32 subnetwork = makeAddr("hints-subnetwork").subnetwork(0);
        _createNetworkSlot(group, subnetwork, 444);
        uint96 networkSlot = group.createIndex(uint32(1));

        _createOperatorSlot(networkSlot, alice, 444);
        uint96 operatorSlot = networkSlot.createIndex(uint32(1));

        vm.warp(1);
        delegator.setSize(operatorSlot, 222);

        vm.warp(2);
        delegator.setSize(operatorSlot, 0);

        uint48 timestampBeforeSlash = uint48(block.timestamp);
        uint208 pendingBefore = delegator.getPendingAt(operatorSlot, timestampBeforeSlash, 0);
        uint208 childrenPendingBefore = delegator.getChildrenPendingAt(networkSlot, timestampBeforeSlash, 0);
        uint256 availableBefore = delegator.getAvailableAt(networkSlot, timestampBeforeSlash, 0);
        uint256 allocatedBefore = delegator.getAllocatedAt(operatorSlot, timestampBeforeSlash, 0);
        assertGt(pendingBefore, 0);
        assertGt(childrenPendingBefore, 0);

        vm.prank(address(slasher));
        delegator.onSlash(subnetwork, alice, 20, bytes(""));
        uint48 timestampAfterSlash = uint48(block.timestamp);
        uint208 pendingAfter = delegator.getPendingAt(operatorSlot, timestampAfterSlash, 0);
        uint208 childrenPendingAfter = delegator.getChildrenPendingAt(networkSlot, timestampAfterSlash, 0);
        uint256 availableAfter = delegator.getAvailableAt(networkSlot, timestampAfterSlash, 0);
        uint256 allocatedAfter = delegator.getAllocatedAt(operatorSlot, timestampAfterSlash, 0);

        assertLe(pendingAfter, pendingBefore);
        assertLe(childrenPendingAfter, childrenPendingBefore);
        assertLe(availableAfter, availableBefore);
        assertLe(allocatedAfter, allocatedBefore);
    }

    function test_sharedGroup_allowsNetworkRestaking_betweenDepth2Siblings() public {
        _deposit(alice, 100);

        _createSlot(0, true, 100);
        uint96 group = _rootIndex(uint32(1));

        _createSlot(group, false, 80);
        _createSlot(group, false, 80);
        uint96 net1 = group.createIndex(uint32(1));
        uint96 net2 = group.createIndex(uint32(2));

        assertEq(delegator.getAllocated(group, 0), 100);
        assertEq(delegator.getAllocated(net1, 0), 80);
        assertEq(delegator.getAllocated(net2, 0), 80);
    }

    function test_depth3Operators_areIsolatedWithinNetwork() public {
        _deposit(alice, 100);

        _createSlot(0, true, 100);
        uint96 group = _rootIndex(uint32(1));

        _createSlot(group, false, 80);
        uint96 net1 = group.createIndex(uint32(1));

        _createSlot(net1, false, 50);
        _createSlot(net1, false, 50);
        uint96 op1 = net1.createIndex(uint32(1));
        uint96 op2 = net1.createIndex(uint32(2));

        assertEq(delegator.getAllocated(net1, 0), 80);
        assertEq(delegator.getAllocated(op1, 0), 50);
        assertEq(delegator.getAllocated(op2, 0), 30);
    }

    function test_isolatedGroups_prioritizedOverTime() public {
        _createSlot(0, false, 30);
        _createSlot(0, false, 50);
        _createSlot(0, false, 100);

        uint96 slot1 = _rootIndex(uint32(1));
        uint96 slot2 = _rootIndex(uint32(2));
        uint96 slot3 = _rootIndex(uint32(3));

        vm.warp(1);
        _deposit(alice, 60);

        assertEq(delegator.getAllocatedAt(slot1, 1, 0), 30);
        assertEq(delegator.getAllocatedAt(slot2, 1, 0), 30);
        assertEq(delegator.getAllocatedAt(slot3, 1, 0), 0);

        vm.warp(2);
        _deposit(alice, 60);

        assertEq(delegator.getAllocatedAt(slot1, 2, 0), 30);
        assertEq(delegator.getAllocatedAt(slot2, 2, 0), 50);
        assertEq(delegator.getAllocatedAt(slot3, 2, 0), 40);
    }

    function test_isolatedNetworks_followGroupPriority() public {
        _deposit(alice, 150);

        _createSlot(0, false, 200);
        uint96 group = _rootIndex(uint32(1));

        _createSlot(group, false, 60);
        _createSlot(group, false, 120);
        uint96 net1 = group.createIndex(uint32(1));
        uint96 net2 = group.createIndex(uint32(2));

        assertEq(delegator.getAllocated(group, 0), 150);
        assertEq(delegator.getAllocated(net1, 0), 60);
        assertEq(delegator.getAllocated(net2, 0), 90);
    }

    function test_isolatedOperators_prioritizedAfterStakeDecrease() public {
        _createSlot(0, false, 1000);
        uint96 group = _rootIndex(uint32(1));

        _createSlot(group, false, 1000);
        uint96 networkSlot = group.createIndex(uint32(1));

        _createSlot(networkSlot, false, 70);
        _createSlot(networkSlot, false, 70);
        uint96 op1 = networkSlot.createIndex(uint32(1));
        uint96 op2 = networkSlot.createIndex(uint32(2));

        vm.warp(1);
        _deposit(alice, 100);

        assertEq(delegator.getAllocated(op1, 0), 70);
        assertEq(delegator.getAllocated(op2, 0), 30);

        vm.warp(2);
        _withdraw(alice, 40);

        assertEq(delegator.getAllocated(op1, 0), 70);
        assertEq(delegator.getAllocated(op2, 0), 30);
    }

    function test_isolatedSlots_childrenPending_delaysReallocation() public {
        _deposit(alice, 100);

        _createSlot(0, false, 70);
        _createSlot(0, false, 70);
        uint96 slot1 = _rootIndex(uint32(1));
        uint96 slot2 = _rootIndex(uint32(2));

        assertEq(delegator.getAllocated(slot1, 0), 70);
        assertEq(delegator.getAllocated(slot2, 0), 30);

        vm.warp(1);
        delegator.setSize(slot1, 30);

        assertEq(delegator.getAvailable(0, 0), 60);
        assertEq(delegator.getAllocated(slot1, 0), 70);
        assertEq(delegator.getAllocated(slot2, 0), 30);

        vm.warp(1 + EPOCH_DURATION);
        assertEq(delegator.getAvailable(0, 0), 100);
        assertEq(delegator.getAllocated(slot1, 0), 30);
        assertEq(delegator.getAllocated(slot2, 0), 70);
    }

    function test_isolatedSlots_lateSizeIncrease_doesNotAffectEarlier() public {
        _deposit(alice, 90);

        _createSlot(0, false, 50);
        _createSlot(0, false, 60);
        uint96 slot1 = _rootIndex(uint32(1));
        uint96 slot2 = _rootIndex(uint32(2));

        assertEq(delegator.getAllocated(slot1, 0), 50);
        assertEq(delegator.getAllocated(slot2, 0), 40);

        vm.warp(1);
        delegator.setSize(slot2, 100);

        assertEq(delegator.getAllocated(slot1, 0), 50);
        assertEq(delegator.getAllocated(slot2, 0), 40);

        vm.warp(2);
        _deposit(alice, 30);

        assertEq(delegator.getAllocated(slot1, 0), 50);
        assertEq(delegator.getAllocated(slot2, 0), 70);
    }

    struct Test_SharedGroupSlashCappedAcrossNetworksSameCaptureTimestampStruct {
        address network1;
        address network2;
        address network3;
        address middleware;
        address operator1;
        address operator2;
        address operator3;
        bytes32 subnetwork1;
        bytes32 subnetwork2;
        bytes32 subnetwork3;
        uint96 group1;
        uint96 group2;
        uint96 netSlot1;
        uint96 netSlot2;
        uint96 netSlot3;
        uint96 opSlot1;
        uint96 opSlot2;
        uint96 opSlot3;
        uint48 captureTimestamp;
    }

    function test_sharedGroup_slashCappedAcrossNetworks_sameCaptureTimestamp() public {
        Test_SharedGroupSlashCappedAcrossNetworksSameCaptureTimestampStruct memory testStruct;

        testStruct.network1 = makeAddr("network1");
        testStruct.network2 = makeAddr("network2");
        testStruct.network3 = makeAddr("network3");
        testStruct.middleware = makeAddr("middleware");
        testStruct.operator1 = alice;
        testStruct.operator2 = bob;
        testStruct.operator3 = makeAddr("charlie");

        _registerNetwork(testStruct.network1, testStruct.middleware);
        _registerNetwork(testStruct.network2, testStruct.middleware);
        _registerNetwork(testStruct.network3, testStruct.middleware);
        _registerOperator(testStruct.operator1);
        _registerOperator(testStruct.operator2);
        _registerOperator(testStruct.operator3);
        _optIn(testStruct.operator1, testStruct.network1);
        _optIn(testStruct.operator2, testStruct.network2);
        _optIn(testStruct.operator3, testStruct.network3);

        testStruct.subnetwork1 = testStruct.network1.subnetwork(0);
        testStruct.subnetwork2 = testStruct.network2.subnetwork(0);
        testStruct.subnetwork3 = testStruct.network3.subnetwork(0);

        _createSlot(0, true, 60);
        _createSlot(0, false, 40);
        testStruct.group1 = _rootIndex(uint32(1));
        testStruct.group2 = _rootIndex(uint32(2));

        _createNetworkSlot(testStruct.group1, testStruct.subnetwork1, 60);
        _createNetworkSlot(testStruct.group1, testStruct.subnetwork2, 60);
        testStruct.netSlot1 = testStruct.group1.createIndex(uint32(1));
        testStruct.netSlot2 = testStruct.group1.createIndex(uint32(2));

        _createOperatorSlot(testStruct.netSlot1, testStruct.operator1, 60);
        testStruct.opSlot1 = testStruct.netSlot1.createIndex(uint32(1));

        _createOperatorSlot(testStruct.netSlot2, testStruct.operator2, 60);
        testStruct.opSlot2 = testStruct.netSlot2.createIndex(uint32(1));

        _createNetworkSlot(testStruct.group2, testStruct.subnetwork3, 40);
        testStruct.netSlot3 = testStruct.group2.createIndex(uint32(1));

        _createOperatorSlot(testStruct.netSlot3, testStruct.operator3, 40);
        testStruct.opSlot3 = testStruct.netSlot3.createIndex(uint32(1));

        _deposit(testStruct.operator1, 100);

        vm.startPrank(testStruct.middleware);
        assertEq(slasher.requestSlash(testStruct.subnetwork1, testStruct.operator1, 60, 0, ""), 0);
        assertEq(slasher.requestSlash(testStruct.subnetwork2, testStruct.operator2, 60, 0, ""), 1);
        assertEq(slasher.requestSlash(testStruct.subnetwork3, testStruct.operator3, 40, 0, ""), 2);
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

        _createSlot(0, true, 60);
        uint96 group = _rootIndex(uint32(1));

        _createNetworkSlot(group, subnetwork1, 60);
        _createNetworkSlot(group, subnetwork2, 60);
        uint96 netSlot1 = group.createIndex(uint32(1));
        uint96 netSlot2 = group.createIndex(uint32(2));

        _createOperatorSlot(netSlot1, operator1, 60);
        uint96 opSlot1 = netSlot1.createIndex(uint32(1));

        _createOperatorSlot(netSlot2, operator2, 60);
        uint96 opSlot2 = netSlot2.createIndex(uint32(1));

        _deposit(alice, 60);

        vm.startPrank(middleware);
        assertEq(slasher.requestSlash(subnetwork1, operator1, 60, 0, ""), 0);
        assertEq(slasher.requestSlash(subnetwork2, operator2, 60, 0, ""), 1);
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

        _createSlot(0, true, 200);
        uint96 group = _rootIndex(uint32(1));

        _createNetworkSlot(group, subnetwork1, 200);
        _createNetworkSlot(group, subnetwork2, 200);
        uint96 netSlot1 = group.createIndex(uint32(1));
        uint96 netSlot2 = group.createIndex(uint32(2));

        _createOperatorSlot(netSlot1, operator1, 200);
        uint96 opSlot1 = netSlot1.createIndex(uint32(1));

        _createOperatorSlot(netSlot2, operator2, 200);
        uint96 opSlot2 = netSlot2.createIndex(uint32(1));

        _deposit(alice, 100);

        vm.startPrank(middleware);
        assertEq(slasher.requestSlash(subnetwork1, operator1, 60, 0, ""), 0);
        assertEq(slasher.requestSlash(subnetwork2, operator2, 60, 0, ""), 1);
        vm.stopPrank();
    }

    function testFuzz_isolatedGroups_followPriority(uint256 depositAmount, uint256 size1, uint256 size2) public {
        uint256 amount = bound(depositAmount, 1, MAX_AMOUNT);
        uint256 cap1 = bound(size1, 0, MAX_AMOUNT);
        uint256 cap2 = bound(size2, 0, MAX_AMOUNT);

        _createSlot(0, false, cap1);
        _createSlot(0, false, cap2);
        uint96 slot1 = _rootIndex(uint32(1));
        uint96 slot2 = _rootIndex(uint32(2));

        _deposit(alice, amount);

        uint256 expected1 = amount < cap1 ? amount : cap1;
        uint256 remaining = amount > cap1 ? amount - cap1 : 0;
        uint256 expected2 = remaining < cap2 ? remaining : cap2;

        assertEq(delegator.getAllocated(slot1, 0), expected1);
        assertEq(delegator.getAllocated(slot2, 0), expected2);
    }

    function testFuzz_isolatedOperators_followPriority(uint256 depositAmount, uint256 size1, uint256 size2) public {
        uint256 amount = bound(depositAmount, 1, MAX_AMOUNT);
        uint256 cap1 = bound(size1, 0, MAX_AMOUNT);
        uint256 cap2 = bound(size2, 0, MAX_AMOUNT);

        _createSlot(0, false, MAX_AMOUNT);
        uint96 group = _rootIndex(uint32(1));

        _createSlot(group, false, MAX_AMOUNT);
        uint96 networkSlot = group.createIndex(uint32(1));

        _createSlot(networkSlot, false, cap1);
        _createSlot(networkSlot, false, cap2);
        uint96 op1 = networkSlot.createIndex(uint32(1));
        uint96 op2 = networkSlot.createIndex(uint32(2));

        _deposit(alice, amount);

        uint256 expected1 = amount < cap1 ? amount : cap1;
        uint256 remaining = amount > expected1 ? amount - expected1 : 0;
        uint256 expected2 = remaining < cap2 ? remaining : cap2;

        assertEq(delegator.getAllocated(op1, 0), expected1);
        assertEq(delegator.getAllocated(op2, 0), expected2);
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

        _createSlot(0, false, cap1);
        _createSlot(0, false, cap2);
        uint96 slot1 = _rootIndex(uint32(1));
        uint96 slot2 = _rootIndex(uint32(2));

        vm.warp(1);
        _deposit(alice, amount);

        uint256 withdraw = bound(withdrawAmount, 0, amount);
        vm.warp(2);
        if (withdraw > 0) {
            _withdraw(alice, withdraw);
        }

        uint256 available = delegator.getAvailable(0, 0);
        uint256 expected1 = available < cap1 ? available : cap1;
        uint256 remaining = available > cap1 ? available - cap1 : 0;
        uint256 expected2 = remaining < cap2 ? remaining : cap2;

        assertEq(delegator.getAllocated(slot1, 0), expected1);
        assertEq(delegator.getAllocated(slot2, 0), expected2);
    }

    function testFuzz_isolatedShares_doNotOverlapAtRoot(uint256 depositAmount, uint256 size1, uint256 size2) public {
        uint256 cap1 = bound(size1, 0, MAX_AMOUNT);
        uint256 cap2 = bound(size2, 0, MAX_AMOUNT);
        uint256 amount = bound(depositAmount, 1, MAX_AMOUNT);

        _createSlot(0, false, cap1);
        _createSlot(0, false, cap2);
        uint96 slot1 = _rootIndex(uint32(1));
        uint96 slot2 = _rootIndex(uint32(2));

        _deposit(alice, amount);

        uint256 available = delegator.getAvailable(0, 0);
        uint256 expected1 = available < cap1 ? available : cap1;
        uint256 remaining = available > cap1 ? available - cap1 : 0;
        uint256 expected2 = remaining < cap2 ? remaining : cap2;

        assertEq(delegator.getAllocated(slot1, 0), expected1);
        assertEq(delegator.getAllocated(slot2, 0), expected2);
    }

    function testFuzz_isolatedShares_doNotOverlapInGroup(uint256 depositAmount, uint256 size1, uint256 size2) public {
        uint256 cap1 = bound(size1, 0, MAX_AMOUNT);
        uint256 cap2 = bound(size2, 0, MAX_AMOUNT);
        uint256 amount = bound(depositAmount, 1, MAX_AMOUNT);

        _createSlot(0, false, MAX_AMOUNT);
        uint96 group = _rootIndex(uint32(1));

        _createSlot(group, false, cap1);
        _createSlot(group, false, cap2);
        uint96 slot1 = group.createIndex(uint32(1));
        uint96 slot2 = group.createIndex(uint32(2));

        _deposit(alice, amount);

        uint256 available = delegator.getAvailable(group, 0);
        uint256 expected1 = available < cap1 ? available : cap1;
        uint256 remaining = available > expected1 ? available - expected1 : 0;
        uint256 expected2 = remaining < cap2 ? remaining : cap2;
        uint256 totalSize = cap1 + cap2;

        assertEq(delegator.getAllocated(slot1, 0), expected1);
        assertEq(delegator.getAllocated(slot2, 0), expected2);
        assertEq(expected1 + expected2, available < totalSize ? available : totalSize);
    }

    struct Test_CaptureInvariantAcrossNetworksStruct {
        address network1;
        address network2;
        address middleware;
        address operator1;
        address operator2;
        uint256 cap1;
        uint256 cap2;
        uint256 amount;
        uint96 group;
        uint96 networkSlot1;
        uint96 networkSlot2;
        bytes32 subnetwork1;
        bytes32 subnetwork2;
        uint96 opSlot1;
        uint96 opSlot2;
        uint48 captureTimestamp;
        uint256 slashableBefore;
        uint256 slashableAfter;
    }

    function testFuzz_isolatedShares_captureInvariantAcrossNetworks(uint256 depositAmount, uint256 size1, uint256 size2)
        public
    {
        Test_CaptureInvariantAcrossNetworksStruct memory testStruct;

        testStruct.network1 = makeAddr("network1");
        testStruct.network2 = makeAddr("network2");
        testStruct.middleware = makeAddr("middleware");
        testStruct.operator1 = alice;
        testStruct.operator2 = bob;

        _registerNetwork(testStruct.network1, testStruct.middleware);
        _registerNetwork(testStruct.network2, testStruct.middleware);
        _registerOperator(testStruct.operator1);
        _registerOperator(testStruct.operator2);
        _optIn(testStruct.operator1, testStruct.network1);
        _optIn(testStruct.operator2, testStruct.network2);

        testStruct.cap1 = bound(size1, 1, MAX_AMOUNT);
        testStruct.cap2 = bound(size2, 0, MAX_AMOUNT);
        testStruct.amount = bound(depositAmount, 1, MAX_AMOUNT);

        _createSlot(0, false, MAX_AMOUNT);
        testStruct.group = _rootIndex(uint32(1));

        testStruct.subnetwork1 = testStruct.network1.subnetwork(0);
        testStruct.subnetwork2 = testStruct.network2.subnetwork(0);
        _createNetworkSlot(testStruct.group, testStruct.subnetwork1, testStruct.cap1);
        _createNetworkSlot(testStruct.group, testStruct.subnetwork2, testStruct.cap2);
        testStruct.networkSlot1 = testStruct.group.createIndex(uint32(1));
        testStruct.networkSlot2 = testStruct.group.createIndex(uint32(2));

        _createOperatorSlot(testStruct.networkSlot1, testStruct.operator1, testStruct.cap1);
        testStruct.opSlot1 = testStruct.networkSlot1.createIndex(uint32(1));

        _createOperatorSlot(testStruct.networkSlot2, testStruct.operator2, testStruct.cap2);
        testStruct.opSlot2 = testStruct.networkSlot2.createIndex(uint32(1));

        _deposit(testStruct.operator1, testStruct.amount);
        testStruct.captureTimestamp = 0;
        testStruct.slashableBefore =
            slasher.slashableStake(testStruct.subnetwork1, testStruct.operator1, testStruct.captureTimestamp, "");

        delegator.setSize(testStruct.networkSlot1, uint128(testStruct.cap1 - 1));

        testStruct.slashableAfter =
            slasher.slashableStake(testStruct.subnetwork1, testStruct.operator1, testStruct.captureTimestamp, "");
        assertLe(testStruct.slashableAfter, testStruct.slashableBefore);
    }

    struct Test_CaptureInvariantAcrossOperatorsStruct {
        address network;
        address middleware;
        address operator1;
        address operator2;
        uint256 cap1;
        uint256 cap2;
        uint256 networkSize;
        uint256 amount;
        uint96 group;
        uint96 networkSlot;
        bytes32 subnetwork;
        uint96 opSlot1;
        uint96 opSlot2;
        uint256 slashableBefore;
        uint256 slashableAfter;
    }

    function testFuzz_isolatedShares_captureInvariantAcrossOperators(
        uint256 depositAmount,
        uint256 size1,
        uint256 size2
    ) public {
        Test_CaptureInvariantAcrossOperatorsStruct memory testStruct;

        testStruct.network = makeAddr("network");
        testStruct.middleware = makeAddr("middleware");
        testStruct.operator1 = alice;
        testStruct.operator2 = bob;

        _registerNetwork(testStruct.network, testStruct.middleware);
        _registerOperator(testStruct.operator1);
        _registerOperator(testStruct.operator2);
        _optIn(testStruct.operator1, testStruct.network);
        _optIn(testStruct.operator2, testStruct.network);

        uint256 cap1 = bound(size1, 1, MAX_AMOUNT);
        uint256 cap2 = bound(size2, 0, MAX_AMOUNT);
        uint256 networkSize = cap1 + cap2;
        uint256 amount = bound(depositAmount, 1, MAX_AMOUNT);

        _createSlot(0, false, MAX_AMOUNT);
        uint96 group = _rootIndex(uint32(1));

        testStruct.subnetwork = testStruct.network.subnetwork(0);
        _createNetworkSlot(group, testStruct.subnetwork, networkSize);
        uint96 networkSlot = group.createIndex(uint32(1));

        _createOperatorSlot(networkSlot, testStruct.operator1, cap1);
        _createOperatorSlot(networkSlot, testStruct.operator2, cap2);
        uint96 opSlot1 = networkSlot.createIndex(uint32(1));
        uint96 opSlot2 = networkSlot.createIndex(uint32(2));

        _deposit(testStruct.operator1, amount);
        uint48 captureTimestamp = 0;

        uint256 slashableBefore =
            slasher.slashableStake(testStruct.subnetwork, testStruct.operator1, captureTimestamp, "");

        delegator.setSize(opSlot1, uint128(cap1 - 1));

        uint256 slashableAfter =
            slasher.slashableStake(testStruct.subnetwork, testStruct.operator1, captureTimestamp, "");
        assertLe(slashableAfter, slashableBefore);
    }

    function test_isShared_trueWhenGroupIsShared() public {
        bytes32 subnetwork = bytes32(uint256(1));

        _deposit(alice, 100);

        _createSlot(0, true, 100);
        uint96 group = _rootIndex(uint32(1));

        _createNetworkSlot(group, subnetwork, 100);
        uint96 networkSlot = group.createIndex(uint32(1));

        _createOperatorSlot(networkSlot, alice, 100);
        uint96 operatorSlot = networkSlot.createIndex(uint32(1));

        assertTrue(delegator.getIsShared(subnetwork));
    }

    function test_isShared_falseWhenGroupNotShared() public {
        bytes32 subnetwork = bytes32(uint256(1));

        _deposit(alice, 100);

        _createSlot(0, false, 100);
        uint96 group = _rootIndex(uint32(1));

        _createNetworkSlot(group, subnetwork, 100);
        uint96 networkSlot = group.createIndex(uint32(1));

        _createOperatorSlot(networkSlot, alice, 100);
        uint96 operatorSlot = networkSlot.createIndex(uint32(1));

        assertFalse(delegator.getIsShared(subnetwork));
    }

    function test_onlyRoles_enforced() public {
        vm.startPrank(bob);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, bob, CREATE_SLOT_ROLE)
        );
        _createSlot(0, false, 1);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, bob, SET_SIZE_ROLE)
        );
        delegator.setSize(_rootIndex(uint32(1)), 1);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, bob, SWAP_SLOTS_ROLE)
        );
        delegator.swapSlots(_rootIndex(uint32(1)), _rootIndex(uint32(2)));

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, bob, REMOVE_SLOT_ROLE)
        );
        delegator.removeSlot(_rootIndex(uint32(1)));

        vm.stopPrank();
    }

    function test_depthGuards_enforced() public {
        _createSlot(0, false, 100);
        uint96 group = _rootIndex(uint32(1));

        _createSlot(group, false, 100);

        vm.expectRevert(IUniversalDelegator.WrongDepth.selector);
        _createSlot(group, true, 1);
    }

    function test_networkAssignment_duplicateAndUnassignChecks() public {
        bytes32 subnetwork = bytes32(uint256(1));

        _createSlot(0, false, 100);
        uint96 group = _rootIndex(uint32(1));

        _createNetworkSlot(group, subnetwork, 100);
        uint96 net1 = group.createIndex(uint32(1));

        assertEq(delegator.getSlotOfNetwork(subnetwork), net1);

        vm.expectRevert(IUniversalDelegator.AlreadyAssigned.selector);
        _createNetworkSlot(group, subnetwork, 100);
    }

    function test_networkAssignment_revertsWhenSlotAlreadyAssigned() public {
        bytes32 subnetwork1 = bytes32(uint256(1));
        bytes32 subnetwork2 = bytes32(uint256(2));

        _createSlot(0, false, 100);
        uint96 group1 = _rootIndex(uint32(1));

        _createSlot(0, false, 100);
        uint96 group2 = _rootIndex(uint32(2));

        _createNetworkSlot(group1, subnetwork1, 100);
        uint96 networkSlot1 = group1.createIndex(uint32(1));

        vm.expectRevert(IUniversalDelegator.AlreadyAssigned.selector);
        _createNetworkSlot(group2, subnetwork1, 100);

        _createNetworkSlot(group2, subnetwork2, 100);
        uint96 networkSlot2 = group2.createIndex(uint32(1));

        assertEq(delegator.getSlotOfNetwork(subnetwork1), networkSlot1);
        assertEq(delegator.getSlotOfNetwork(subnetwork2), networkSlot2);
    }

    function test_operatorAssignment_duplicateAndUnassignChecks() public {
        _createSlot(0, false, 100);
        uint96 group = _rootIndex(uint32(1));

        bytes32 subnetwork = bytes32(uint256(1));
        _createNetworkSlot(group, subnetwork, 100);
        uint96 networkSlot = group.createIndex(uint32(1));

        _createOperatorSlot(networkSlot, alice, 60);
        uint96 operatorSlot1 = networkSlot.createIndex(uint32(1));

        assertEq(delegator.getSlotOfOperator(networkSlot, alice), operatorSlot1);

        vm.expectRevert(IUniversalDelegator.AlreadyAssigned.selector);
        _createOperatorSlot(networkSlot, alice, 60);
    }

    function test_operatorAssignment_revertsWhenSlotAlreadyAssigned() public {
        _createSlot(0, false, 100);
        uint96 group = _rootIndex(uint32(1));

        bytes32 subnetwork = bytes32(uint256(1));
        _createNetworkSlot(group, subnetwork, 100);
        uint96 networkSlot = group.createIndex(uint32(1));

        _createOperatorSlot(networkSlot, alice, 100);
        uint96 operatorSlot = networkSlot.createIndex(uint32(1));

        vm.expectRevert(IUniversalDelegator.AlreadyAssigned.selector);
        _createOperatorSlot(networkSlot, alice, 100);

        assertEq(delegator.getSlotOfOperator(networkSlot, alice), operatorSlot);
    }

    function test_swapSlots_keepsAllocationAfterStakeDecrease() public {
        _deposit(alice, 100);

        _createSlot(0, false, 30);
        _createSlot(0, false, 50);

        uint96 slot1 = _rootIndex(uint32(1));
        uint96 slot2 = _rootIndex(uint32(2));

        vm.warp(1);
        delegator.swapSlots(slot1, slot2);

        vm.warp(2);
        _withdraw(alice, 60);

        assertEq(delegator.getAllocated(slot2, 0), 50);
        assertEq(delegator.getAllocated(slot1, 0), 30);
    }

    function test_swapSlots_revertsWrongOrder() public {
        _createSlot(0, false, 10);
        _createSlot(0, false, 10);
        uint96 slot1 = _rootIndex(uint32(1));
        uint96 slot2 = _rootIndex(uint32(2));

        vm.expectRevert(IUniversalDelegator.WrongOrder.selector);
        delegator.swapSlots(slot2, slot1);
    }

    function test_swapSlots_adjacentTail_preservesLinks() public {
        _createSlot(0, false, 10);
        _createSlot(0, false, 10);
        _createSlot(0, false, 10);

        uint96 slot1 = _rootIndex(uint32(1));
        uint96 slot2 = _rootIndex(uint32(2));
        uint96 slot3 = _rootIndex(uint32(3));

        delegator.swapSlots(slot2, slot3);

        IUniversalDelegator.Slot memory rootAfter = delegator.getSlot(0);
        IUniversalDelegator.Slot memory slot2After = delegator.getSlot(slot2);
        IUniversalDelegator.Slot memory slot3After = delegator.getSlot(slot3);

        assertEq(rootAfter.firstChild, slot1.getChildIndex());
        assertEq(rootAfter.lastChild, slot2.getChildIndex());
        assertEq(slot3After.prevSlot, slot1.getChildIndex());
        assertEq(slot3After.nextSlot, slot2.getChildIndex());
        assertEq(slot2After.prevSlot, slot3.getChildIndex());
    }

    function test_swapSlots_revertsNotSameParent() public {
        _deposit(alice, 100);

        _createSlot(0, false, 10);
        uint96 rootSlot = _rootIndex(uint32(1));

        _createSlot(0, false, 10);
        uint96 group = _rootIndex(uint32(2));
        _createSlot(group, false, 10);
        uint96 networkSlot = group.createIndex(uint32(1));

        vm.expectRevert(IUniversalDelegator.NotSameParent.selector);
        delegator.swapSlots(rootSlot, networkSlot);
    }

    function test_swapSlots_revertsNotSameAllocated() public {
        _deposit(alice, 50);

        _createSlot(0, false, 100);
        uint96 group = _rootIndex(uint32(1));

        _createSlot(group, false, 50);
        _createSlot(group, false, 50);
        uint96 slot1 = group.createIndex(uint32(1));
        uint96 slot2 = group.createIndex(uint32(2));

        vm.expectRevert(IUniversalDelegator.NotSameAllocated.selector);
        delegator.swapSlots(slot1, slot2);
    }

    function test_swapSlots_revertsPartiallyAllocated() public {
        _deposit(alice, 70);

        _createSlot(0, false, 100);
        uint96 group = _rootIndex(uint32(1));

        _createSlot(group, false, 50);
        _createSlot(group, false, 50);
        uint96 slot1 = group.createIndex(uint32(1));
        uint96 slot2 = group.createIndex(uint32(2));

        vm.expectRevert(IUniversalDelegator.PartiallyAllocated.selector);
        delegator.swapSlots(slot1, slot2);
    }

    function test_getAvailableAt_doesNotUnderflowForSmallTimestamps() public {
        _deposit(alice, 100);

        _createSlot(0, false, 60);
        uint96 slot1 = _rootIndex(uint32(1));

        vm.warp(1);
        delegator.setSize(slot1, 40);

        assertEq(delegator.getAvailableAt(0, 2, EPOCH_DURATION), 100);
        assertEq(delegator.getAvailableAt(0, 4, EPOCH_DURATION), 100);
    }

    function test_miscViewsAndDeprecatedMethods() public {
        assertEq(delegator.VERSION(), 2);
        assertEq(delegator.maxNetworkLimit(bytes32(0)), type(uint256).max);
        delegator.setMaxNetworkLimit(1, 123);
        assertEq(delegator.getWithdrawalBuffer(), 0);
    }

    function test_slotExists_revertsForMissingSlot() public {
        vm.expectRevert(IUniversalDelegator.SlotNotCreated.selector);
        delegator.setSize(_rootIndex(uint32(1)), 1);
    }

    function test_modifiers_slotExistsAndSyncPrevSums_harness() public {
        UniversalDelegatorCoverageHarness harness = new UniversalDelegatorCoverageHarness();

        vm.expectRevert(IUniversalDelegator.SlotNotCreated.selector);
        harness.exposeSlotExists(_rootIndex(uint32(1)));

        harness.setSlotExistsRaw(_rootIndex(uint32(1)), true);
        harness.exposeSlotExists(_rootIndex(uint32(1)));

        harness.setNeedPrevSumsSyncRaw(0, true);
        harness.exposeSyncPrevSums(0);
        assertFalse(harness.needPrevSumsSyncRaw(0));
    }

    function test_modifiers_syncPrevSums_harness_withChildren() public {
        UniversalDelegatorCoverageHarness harness = new UniversalDelegatorCoverageHarness();

        uint96 parent = _rootIndex(uint32(1));
        uint96 child1 = parent.createIndex(uint32(1));
        uint96 child2 = parent.createIndex(uint32(2));

        harness.setSlotExistsRaw(parent, true);
        harness.setSlotExistsRaw(child1, true);
        harness.setSlotExistsRaw(child2, true);

        harness.setParentChildrenRaw(parent, 1, 2, 2);
        harness.setSlotLinksRaw(child1, 0, 2);
        harness.setSlotLinksRaw(child2, 1, 0);
        harness.pushSizeRaw(child1, 1, 5);
        harness.pushSizeRaw(child2, 1, 7);
        harness.setNeedPrevSumsSyncRaw(parent, true);

        harness.exposeSyncPrevSums(parent);

        assertFalse(harness.needPrevSumsSyncRaw(parent));
        assertEq(harness.prevSumLatestRaw(child1), 0);
        assertEq(harness.prevSumLatestRaw(child2), 5);
    }

    function test_createSlot_revertsForMissingParentSlot() public {
        vm.expectRevert(IUniversalDelegator.SlotNotCreated.selector);
        delegator.createSlot(bytes32(0), _rootIndex(uint32(1)), false, false, 1);
    }

    function test_slotExists_revertsForMissingSlot_swapAndRemove() public {
        vm.expectRevert(IUniversalDelegator.SlotNotCreated.selector);
        delegator.swapSlots(_rootIndex(uint32(1)), _rootIndex(uint32(2)));

        delegator.grantRole(REMOVE_SLOT_ROLE, owner);
        vm.expectRevert(IUniversalDelegator.SlotNotCreated.selector);
        delegator.removeSlot(_rootIndex(uint32(1)));
    }

    function test_syncPrevSums_pathForNonRootParent_afterSlash() public {
        _deposit(alice, 100);

        bytes32 subnetwork = makeAddr("non-root-sync-subnetwork").subnetwork(0);
        _createSlot(0, false, 100);
        uint96 group = _rootIndex(uint32(1));
        _createNetworkSlot(group, subnetwork, 100);
        uint96 networkSlot = group.createIndex(uint32(1));
        _createOperatorSlot(networkSlot, alice, 60);
        _createOperatorSlot(networkSlot, bob, 40);
        uint96 operatorSlot = networkSlot.createIndex(uint32(1));

        vm.prank(address(slasher));
        delegator.onSlash(subnetwork, alice, 1, bytes(""));

        uint128 currentSize = delegator.getSlot(operatorSlot).size;
        uint208 pending = delegator.setSize(operatorSlot, currentSize);
        assertEq(pending, 0);
    }

    function test_syncPrevSums_modifier_clearsInjectedFlag() public {
        _deposit(alice, 100);

        _createSlot(0, false, 100);
        uint96 group = _rootIndex(uint32(1));
        _createSlot(group, false, 60);
        uint96 child = group.createIndex(uint32(1));

        bytes32 groupSlot = keccak256(abi.encode(uint256(group), uint256(3)));
        bytes32 groupData = vm.load(address(delegator), groupSlot);
        bytes32 groupDataWithFlag = groupData | bytes32(uint256(1) << (27 * 8));
        vm.store(address(delegator), groupSlot, groupDataWithFlag);
        bytes32 groupDataBefore = vm.load(address(delegator), groupSlot);
        assertEq((uint256(groupDataBefore) >> (27 * 8)) & 0xFF, 1);

        uint128 currentSize = delegator.getSlot(child).size;
        uint208 pending = delegator.setSize(child, currentSize);
        assertEq(pending, 0);

        bytes32 groupDataAfter = vm.load(address(delegator), groupSlot);
        assertEq((uint256(groupDataAfter) >> (27 * 8)) & 0xFF, 0);
    }

    function test_viewWrappersAndHints() public {
        _deposit(alice, 100);

        address network = makeAddr("wrap-network");
        bytes32 subnetwork = network.subnetwork(0);

        _createSlot(0, false, 100);
        uint96 group = _rootIndex(uint32(1));
        _createNetworkSlot(group, subnetwork, 100);
        uint96 networkSlot = group.createIndex(uint32(1));
        _createOperatorSlot(networkSlot, alice, 80);
        uint96 operatorSlot = networkSlot.createIndex(uint32(1));

        assertEq(delegator.stake(subnetwork, alice), 80);
        assertEq(delegator.stakeFor(subnetwork, alice, 0), 80);
        assertEq(delegator.stakeForAt(subnetwork, alice, 0, uint48(block.timestamp)), 80);
        assertEq(delegator.stakeAt(subnetwork, alice, uint48(block.timestamp), ""), 80);

        assertEq(delegator.getSlotOfNetworkAt(subnetwork, uint48(block.timestamp)), networkSlot);
        assertEq(delegator.getSlotOfNetwork(subnetwork), networkSlot);
        assertEq(delegator.getSlotOfOperatorAt(networkSlot, alice, uint48(block.timestamp)), operatorSlot);
        assertEq(delegator.getSlotOfOperator(networkSlot, alice), operatorSlot);
        assertEq(delegator.getSlotOfAt(subnetwork, alice, uint48(block.timestamp)), operatorSlot);
        assertEq(delegator.getSlotOf(subnetwork, alice), operatorSlot);

        assertEq(delegator.getAllocatedAt(subnetwork, alice, uint48(block.timestamp), 0), 80);
        assertEq(delegator.getAllocated(subnetwork, alice, 0), 80);
        assertEq(delegator.getAllocatedAt(operatorSlot, uint48(block.timestamp), EPOCH_DURATION + 1), 0);
        assertEq(delegator.getAllocated(operatorSlot, EPOCH_DURATION + 1), 0);

        assertEq(delegator.getBalanceAt(operatorSlot, uint48(block.timestamp), 0), 80);
        assertEq(delegator.getBalanceAt(0, uint48(block.timestamp), 0), 100);
        assertEq(delegator.getBalance(operatorSlot, 0), 80);
        assertEq(delegator.getAvailableAt(operatorSlot, uint48(block.timestamp), 0), 80);
        assertEq(delegator.getAvailable(operatorSlot, 0), 80);
        assertEq(delegator.getPendingAt(operatorSlot, uint48(block.timestamp), 0), 0);
        assertEq(delegator.getPending(operatorSlot, 0), 0);
        assertEq(delegator.getChildrenPendingAt(networkSlot, uint48(block.timestamp), 0), 0);
        assertEq(delegator.getChildrenPending(networkSlot, 0), 0);
    }

    function test_assignmentFlags_revertWhenNotAssigned() public {
        bytes32 subnetwork = makeAddr("not-assigned").subnetwork(0);

        vm.expectRevert(IUniversalDelegator.NotAssigned.selector);
        delegator.getIsShared(subnetwork);

        vm.expectRevert(IUniversalDelegator.NotAssigned.selector);
        delegator.getIsNoPlugins(subnetwork);
    }

    function test_createSlot_noPluginsAndSetSizeNoPlugins() public {
        vm.expectRevert(IUniversalDelegator.NotEnoughNoPlugins.selector);
        delegator.createSlot(bytes32(0), 0, false, true, 1);

        _deposit(alice, 100);

        uint96 group = delegator.createSlot(bytes32(0), 0, false, true, 40);
        bytes32 subnetwork = makeAddr("no-plugins-network").subnetwork(0);
        delegator.createSlot(subnetwork, group, false, false, 40);

        assertTrue(delegator.getIsNoPlugins(subnetwork));
        assertEq(delegator.getNoPluginsSize(), 40);

        vm.expectRevert(IUniversalDelegator.NotEnoughNoPlugins.selector);
        delegator.setSize(group, 200);

        vm.warp(1);
        uint208 pending = delegator.setSize(group, 10);
        assertEq(pending, 30);
        assertEq(delegator.getNoPluginsSize(), 40);

        vm.warp(EPOCH_DURATION + 1);
        assertEq(delegator.getNoPluginsSize(), 10);
    }

    function test_createSlot_revertsTooManyGroups() public {
        for (uint256 i; i < MAX_GROUPS; ++i) {
            _createSlot(0, false, 0);
        }

        vm.expectRevert(IUniversalDelegator.TooManyChildren.selector);
        _createSlot(0, false, 0);
    }

    function test_createSlot_revertsTooManyNetworksPerGroup() public {
        _createSlot(0, false, 0);
        uint96 group = _rootIndex(uint32(1));

        for (uint256 i; i < MAX_NETWORKS; ++i) {
            bytes32 subnetwork = bytes32(i + 1);
            delegator.createSlot(subnetwork, group, false, false, 0);
        }

        vm.expectRevert(IUniversalDelegator.TooManyChildren.selector);
        delegator.createSlot(bytes32(MAX_NETWORKS + 1), group, false, false, 0);
    }

    function test_createSlot_revertsTooManyOperatorsPerNetwork() public {
        _createSlot(0, false, 0);
        uint96 group = _rootIndex(uint32(1));
        uint96 networkSlot = delegator.createSlot(bytes32("network"), group, false, false, 0);

        for (uint256 i; i < MAX_OPERATORS; ++i) {
            address operator = address(uint160(i + 1));
            delegator.createSlot(_operatorKey(operator), networkSlot, false, false, 0);
        }

        vm.expectRevert(IUniversalDelegator.TooManyChildren.selector);
        delegator.createSlot(_operatorKey(address(uint160(MAX_OPERATORS + 1))), networkSlot, false, false, 0);
    }

    function test_swapSlots_revertsIsShared() public {
        _deposit(alice, 100);
        _createSlot(0, true, 100);
        uint96 group = _rootIndex(uint32(1));
        _createSlot(group, false, 50);
        _createSlot(group, false, 50);

        vm.expectRevert(IUniversalDelegator.IsShared.selector);
        delegator.swapSlots(group.createIndex(uint32(1)), group.createIndex(uint32(2)));
    }

    function test_removeSlot_revertsWhenAllocated() public {
        delegator.grantRole(REMOVE_SLOT_ROLE, owner);
        _deposit(alice, 100);
        _createSlot(0, false, 100);
        uint96 slot = _rootIndex(uint32(1));

        vm.expectRevert(IUniversalDelegator.SlotAllocated.selector);
        delegator.removeSlot(slot);
    }

    function test_removeSlot_clearsNetworkAndOperatorAssignments() public {
        delegator.grantRole(REMOVE_SLOT_ROLE, owner);
        _createSlot(0, false, 100);
        uint96 group = _rootIndex(uint32(1));

        bytes32 subnetwork1 = makeAddr("remove-network-1").subnetwork(0);
        bytes32 subnetwork2 = makeAddr("remove-network-2").subnetwork(0);
        bytes32 subnetwork3 = makeAddr("remove-network-3").subnetwork(0);
        delegator.createSlot(subnetwork1, group, false, false, 0);
        delegator.createSlot(subnetwork2, group, false, false, 0);
        delegator.createSlot(subnetwork3, group, false, false, 0);
        uint96 networkSlot1 = group.createIndex(uint32(1));
        uint96 networkSlot2 = group.createIndex(uint32(2));

        delegator.removeSlot(networkSlot2);
        assertEq(delegator.getSlotOfNetwork(subnetwork2), 0);

        delegator.createSlot(_operatorKey(alice), networkSlot1, false, false, 0);
        uint96 operatorSlot = networkSlot1.createIndex(uint32(1));
        delegator.removeSlot(operatorSlot);
        assertEq(delegator.getSlotOfOperator(networkSlot1, alice), 0);
    }

    function test_resetAllocation_revertsUnauthorizedAndNotAssigned() public {
        address network = makeAddr("reset-network");
        address middleware = makeAddr("reset-middleware");
        _registerNetwork(network, middleware);
        bytes32 subnetwork = network.subnetwork(0);

        vm.prank(bob);
        vm.expectRevert(IUniversalDelegator.NotNetworkOrMiddleware.selector);
        delegator.resetAllocation(subnetwork);

        vm.prank(network);
        vm.expectRevert(IUniversalDelegator.NotAssigned.selector);
        delegator.resetAllocation(subnetwork);
    }

    function test_resetAllocation_noPluginsPathAndSyncPrevSums() public {
        address network = makeAddr("reset-network-with-slot");
        address middleware = makeAddr("reset-middleware-with-slot");
        _registerNetwork(network, middleware);
        bytes32 subnetwork = network.subnetwork(0);

        _deposit(alice, 100);

        uint96 noPluginsGroup = delegator.createSlot(bytes32(0), 0, false, true, 80);
        uint96 slot2 = delegator.createSlot(bytes32(0), 0, false, false, 1);
        uint96 slot3 = delegator.createSlot(bytes32(0), 0, false, false, 1);
        delegator.createSlot(subnetwork, noPluginsGroup, false, false, 80);

        vm.warp(1);
        delegator.setSize(noPluginsGroup, 40);
        assertEq(delegator.getNoPluginsSize(), 80);

        vm.prank(network);
        delegator.resetAllocation(subnetwork);

        assertFalse(delegator.getSlot(noPluginsGroup).exists);
        assertEq(delegator.getSlotOfNetwork(subnetwork), 0);
        assertEq(delegator.getNoPluginsSize(), 0);
        assertEq(delegator.getAllocated(slot3, 0), 1);
        assertEq(delegator.getAllocatedAt(slot3, uint48(block.timestamp), 0), 1);

        delegator.setSize(slot2, 2);
        assertEq(delegator.getSlot(slot2).size, 2);
    }

    function test_resetAllocation_singleNetworkClearsAssignmentAndAllowsReassign() public {
        address network = makeAddr("reset-single-network");
        address middleware = makeAddr("reset-single-middleware");
        _registerNetwork(network, middleware);
        bytes32 subnetwork = network.subnetwork(0);

        uint96 group = delegator.createSlot(bytes32(0), 0, false, false, 0);
        uint96 slot = delegator.createSlot(subnetwork, group, false, false, 0);
        assertEq(delegator.getSlotOfNetwork(subnetwork), slot);

        vm.prank(middleware);
        delegator.resetAllocation(subnetwork);

        assertEq(delegator.getSlotOfNetwork(subnetwork), 0);

        uint96 newGroup = delegator.createSlot(bytes32(0), 0, false, false, 0);
        uint96 newSlot = delegator.createSlot(subnetwork, newGroup, false, false, 0);
        assertEq(delegator.getSlotOfNetwork(subnetwork), newSlot);
    }

    function test_onSlash_noPluginsRootDecreasesNoPluginsSize() public {
        _deposit(alice, 100);

        bytes32 subnetwork = makeAddr("no-plugins-on-slash").subnetwork(0);
        uint96 group = delegator.createSlot(bytes32(0), 0, false, true, 80);
        delegator.createSlot(subnetwork, group, false, false, 80);
        uint96 networkSlot = group.createIndex(uint32(1));
        delegator.createSlot(_operatorKey(alice), networkSlot, false, false, 80);

        assertEq(delegator.getNoPluginsSize(), 80);
        assertEq(delegator.getSlot(group).size, 80);

        vm.prank(address(slasher));
        delegator.onSlash(subnetwork, alice, 20, bytes(""));

        assertEq(delegator.getNoPluginsSize(), 60);
        assertEq(delegator.getSlot(group).size, 60);
    }

    function test_setHookAndOnSlashPaths() public {
        vm.expectRevert(IUniversalDelegator.NotSlasher.selector);
        delegator.onSlash(bytes32(0), address(0), 0, "");

        delegator.grantRole(HOOK_SET_ROLE, owner);
        UniversalDelegatorHookMock hookMock = new UniversalDelegatorHookMock();
        delegator.setHook(address(hookMock));

        vm.expectRevert(IUniversalDelegator.AlreadySet.selector);
        delegator.setHook(address(hookMock));

        _deposit(alice, 100);

        bytes32 subnetwork = makeAddr("slash-subnetwork").subnetwork(0);
        uint96 group = delegator.createSlot(bytes32(0), 0, false, true, 80);
        delegator.createSlot(subnetwork, group, false, false, 80);
        uint96 networkSlot = group.createIndex(uint32(1));
        delegator.createSlot(_operatorKey(alice), networkSlot, false, false, 20);
        delegator.createSlot(_operatorKey(bob), networkSlot, false, false, 20);
        uint96 operatorSlot1 = networkSlot.createIndex(uint32(1));
        uint96 operatorSlot2 = networkSlot.createIndex(uint32(2));

        vm.warp(1);
        delegator.setSize(group, 40);
        delegator.setSize(operatorSlot1, 10);

        vm.prank(address(slasher));
        delegator.onSlash(subnetwork, alice, 50, bytes("payload"));

        assertEq(delegator.getPending(operatorSlot1, 0), 0);
        assertEq(delegator.getPending(group, 0), 0);
        assertEq(hookMock.calls(), 1);
        assertEq(hookMock.lastSubnetwork(), subnetwork);
        assertEq(hookMock.lastOperator(), alice);
        assertEq(hookMock.lastAmount(), 50);
        assertEq(hookMock.lastData(), bytes("payload"));
        assertGt(delegator.getAllocated(operatorSlot2, 0), 0);
        assertGt(delegator.getAllocatedAt(operatorSlot2, uint48(block.timestamp), 0), 0);

        uint256 gasToSend = HOOK_RESERVE + HOOK_GAS_LIMIT * 64 / 63 - 1;
        vm.expectRevert(IUniversalDelegator.InsufficientHookGas.selector);
        vm.prank(address(slasher));
        delegator.onSlash{gas: gasToSend}(subnetwork, alice, 1, bytes(""));
    }

    function test_setSize_sameValue_afterSlashSync_returnsZero() public {
        _deposit(alice, 100);

        bytes32 subnetwork = makeAddr("sync-slot-subnetwork").subnetwork(0);
        _createSlot(0, false, 100);
        uint96 group = _rootIndex(uint32(1));
        _createNetworkSlot(group, subnetwork, 100);
        uint96 networkSlot = group.createIndex(uint32(1));
        _createOperatorSlot(networkSlot, alice, 100);

        vm.prank(address(slasher));
        delegator.onSlash(subnetwork, alice, 1, bytes(""));

        uint128 currentSize = delegator.getSlot(group).size;
        uint208 pending = delegator.setSize(group, currentSize);
        assertEq(pending, 0);
    }

    function test_initializeReverts_NotVault_OldVault_MissingRoleHolders() public {
        IUniversalDelegator.InitParams memory params = _defaultDelegatorInitParams();

        vm.expectRevert(IUniversalDelegator.NotVault.selector);
        delegatorFactory.create(0, abi.encode(address(0xBEEF), abi.encode(params)));

        IVault.InitParams memory oldVaultParams = IVault.InitParams({
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
        });
        address oldVault = vaultFactory.create(1, owner, abi.encode(oldVaultParams));

        vm.expectRevert(IUniversalDelegator.OldVault.selector);
        delegatorFactory.create(0, abi.encode(oldVault, abi.encode(params)));

        params.defaultAdminRoleHolder = address(0);
        params.createSlotRoleHolder = address(0);

        vm.expectRevert(IUniversalDelegator.MissingRoleHolders.selector);
        delegatorFactory.create(0, abi.encode(address(vault), abi.encode(params)));
    }

    function test_migrateReverts_WrongMigrate_And_NotMigrating() public {
        vm.mockCall(address(vault), abi.encodeWithSelector(IMigratableEntity.version.selector), abi.encode(uint64(4)));
        vm.expectRevert(IUniversalDelegator.WrongMigrate.selector);
        delegator.migrate();
        vm.clearMockedCalls();

        vm.expectRevert(IUniversalDelegator.NotMigrating.selector);
        delegator.migrate();
    }

    function _requestAndExecuteSlash(bytes32 subnetwork, address operator, uint256 amount, uint48 captureTimestamp)
        internal
        returns (uint256)
    {
        uint256 slashIndex = slasher.requestSlash(subnetwork, operator, amount, captureTimestamp, "");
        return slasher.executeSlash(slashIndex, "");
    }

    function _defaultDelegatorInitParams() internal view returns (IUniversalDelegator.InitParams memory) {
        return IUniversalDelegator.InitParams({
            defaultAdminRoleHolder: owner,
            hook: address(0),
            hookSetRoleHolder: owner,
            createSlotRoleHolder: owner,
            setIsSharedRoleHolder: owner,
            setSizeRoleHolder: owner,
            setShareRoleHolder: owner,
            swapSlotsRoleHolder: owner,
            withdrawalBufferSize: type(uint128).max
        });
    }

    function _createSlot(uint96 parentIndex, bool isShared, uint256 size) internal {
        bytes32 key;
        uint256 depth = parentIndex.getDepth();
        if (depth == 1) {
            ++dummyNetworkId;
            key = DUMMY_NETWORK.subnetwork(dummyNetworkId);
        } else if (depth == 2) {
            ++dummyOperatorId;
            address dummyOperator = address(uint160(DUMMY_OPERATOR_BASE) + dummyOperatorId);
            key = _operatorKey(dummyOperator);
        }
        delegator.createSlot(key, parentIndex, isShared, false, uint128(size));
    }

    function _createNetworkSlot(uint96 parentIndex, bytes32 subnetwork, uint256 size) internal {
        delegator.createSlot(subnetwork, parentIndex, false, false, uint128(size));
    }

    function _createOperatorSlot(uint96 parentIndex, address operator, uint256 size) internal {
        delegator.createSlot(_operatorKey(operator), parentIndex, false, false, uint128(size));
    }

    function _operatorKey(address operator) internal pure returns (bytes32) {
        return bytes32(bytes20(operator));
    }

    function _rootIndex(uint32 localIndex) internal pure returns (uint96) {
        return uint96(0).createIndex(localIndex);
    }

    function _unallocated2(uint96 parentIndex, uint96 slot1, uint96 slot2) internal view returns (uint256) {
        uint256 available = delegator.getAvailable(parentIndex, 0);
        uint256 allocated = delegator.getAllocated(slot1, 0) + delegator.getAllocated(slot2, 0);
        return available > allocated ? available - allocated : 0;
    }

    function _unallocated3(uint96 parentIndex, uint96 slot1, uint96 slot2, uint96 slot3)
        internal
        view
        returns (uint256)
    {
        uint256 available = delegator.getAvailable(parentIndex, 0);
        uint256 allocated =
            delegator.getAllocated(slot1, 0) + delegator.getAllocated(slot2, 0) + delegator.getAllocated(slot3, 0);
        return available > allocated ? available - allocated : 0;
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

contract UniversalDelegatorMigrationTest is Test {
    using Subnetwork for address;

    uint48 internal constant EPOCH_DURATION = 7 days;
    string internal constant VAULT_NAME = "Test";
    string internal constant VAULT_SYMBOL = "TEST";

    address internal owner;
    address internal operator;
    address internal network;

    VaultFactory internal vaultFactory;
    DelegatorFactory internal delegatorFactory;
    SlasherFactory internal slasherFactory;
    NetworkRegistry internal networkRegistry;
    OperatorRegistry internal operatorRegistry;
    NetworkMiddlewareService internal networkMiddlewareService;
    OptInService internal operatorVaultOptInService;
    OptInService internal operatorNetworkOptInService;
    VaultConfigurator internal vaultConfigurator;
    MockRewards internal rewards;

    Token internal collateral;

    function setUp() public {
        owner = address(this);
        operator = makeAddr("operator");
        network = makeAddr("network");

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
        rewards = new MockRewards();

        address vaultImplV1 =
            address(new VaultV1(address(delegatorFactory), address(slasherFactory), address(vaultFactory)));
        vaultFactory.whitelist(vaultImplV1);

        address vaultImplTokenized =
            address(new VaultTokenized(address(delegatorFactory), address(slasherFactory), address(vaultFactory)));
        vaultFactory.whitelist(vaultImplTokenized);

        address vaultImpl = address(
            new VaultV2(address(delegatorFactory), address(slasherFactory), address(vaultFactory), address(rewards))
        );
        vaultFactory.whitelist(vaultImpl);

        address networkRestakeDelegatorImpl = address(
            new NetworkRestakeDelegator(
                address(networkRegistry),
                address(vaultFactory),
                address(operatorVaultOptInService),
                address(operatorNetworkOptInService),
                address(delegatorFactory),
                delegatorFactory.totalTypes()
            )
        );
        delegatorFactory.whitelist(networkRestakeDelegatorImpl);

        address fullRestakeDelegatorImpl = address(
            new FullRestakeDelegator(
                address(networkRegistry),
                address(vaultFactory),
                address(operatorVaultOptInService),
                address(operatorNetworkOptInService),
                address(delegatorFactory),
                delegatorFactory.totalTypes()
            )
        );
        delegatorFactory.whitelist(fullRestakeDelegatorImpl);

        address operatorSpecificDelegatorImpl = address(
            new OperatorSpecificDelegator(
                address(operatorRegistry),
                address(networkRegistry),
                address(vaultFactory),
                address(operatorVaultOptInService),
                address(operatorNetworkOptInService),
                address(delegatorFactory),
                delegatorFactory.totalTypes()
            )
        );
        delegatorFactory.whitelist(operatorSpecificDelegatorImpl);

        address operatorNetworkSpecificDelegatorImpl = address(
            new OperatorNetworkSpecificDelegator(
                address(operatorRegistry),
                address(networkRegistry),
                address(vaultFactory),
                address(operatorVaultOptInService),
                address(operatorNetworkOptInService),
                address(delegatorFactory),
                delegatorFactory.totalTypes()
            )
        );
        delegatorFactory.whitelist(operatorNetworkSpecificDelegatorImpl);

        address universalDelegatorImpl = address(
            new UniversalDelegator(
                address(networkRegistry),
                address(vaultFactory),
                address(delegatorFactory),
                delegatorFactory.totalTypes(),
                address(networkMiddlewareService)
            )
        );
        delegatorFactory.whitelist(universalDelegatorImpl);

        address slasherImpl = address(
            new Slasher(
                address(vaultFactory),
                address(networkMiddlewareService),
                address(slasherFactory),
                slasherFactory.totalTypes()
            )
        );
        slasherFactory.whitelist(slasherImpl);

        address vetoSlasherImpl = address(
            new VetoSlasher(
                address(vaultFactory),
                address(networkMiddlewareService),
                address(networkRegistry),
                address(slasherFactory),
                slasherFactory.totalTypes()
            )
        );
        slasherFactory.whitelist(vetoSlasherImpl);

        address universalSlasherImpl = address(
            new UniversalSlasher(
                address(vaultFactory),
                address(networkMiddlewareService),
                address(networkRegistry),
                address(slasherFactory),
                slasherFactory.totalTypes()
            )
        );
        slasherFactory.whitelist(universalSlasherImpl);

        vm.prank(network);
        networkRegistry.registerNetwork();
        vm.prank(operator);
        operatorRegistry.registerOperator();

        collateral = new Token("Token");
        vaultConfigurator =
            new VaultConfigurator(address(vaultFactory), address(delegatorFactory), address(slasherFactory));
    }

    function test_MigrateLegacyDelegators_ToUniversal() public {
        uint64[] memory delegatorIndices = new uint64[](4);
        delegatorIndices[0] = 0;
        delegatorIndices[1] = 1;
        delegatorIndices[2] = 2;
        delegatorIndices[3] = 3;

        for (uint256 i = 0; i < delegatorIndices.length; ++i) {
            (IVaultV2 vault_, address oldDelegator,) = _createLegacyVault(delegatorIndices[i]);
            bytes memory migrateData = abi.encode(_buildMigrateParams());
            vaultFactory.migrate(address(vault_), vaultFactory.lastVersion(), migrateData);
            _assertDelegatorMigration(vault_, oldDelegator, delegatorIndices[i]);
        }
    }

    function test_MigratedUniversalDelegator_StakeAtBeforeMigrateTimestamp_UsesLegacyPath() public {
        (IVaultV2 vault_, address oldDelegator,) = _createLegacyVault(0);
        vm.warp(10);

        bytes memory migrateData = abi.encode(_buildMigrateParams());
        vaultFactory.migrate(address(vault_), vaultFactory.lastVersion(), migrateData);

        bytes32 subnetwork = network.subnetwork(0);
        uint256 expected = IBaseDelegator(oldDelegator).stakeAt(subnetwork, operator, 9, "");
        uint256 actual = IUniversalDelegator(vault_.delegator()).stakeAt(subnetwork, operator, 9, "");
        assertEq(actual, expected);
    }

    function _createLegacyVault(uint64 delegatorIndex)
        internal
        returns (IVaultV2 vault_, address oldDelegator, address oldSlasher)
    {
        IVault.InitParams memory baseParams = IVault.InitParams({
            collateral: address(collateral),
            burner: address(0xdEaD),
            epochDuration: EPOCH_DURATION,
            depositWhitelist: false,
            isDepositLimit: false,
            depositLimit: 0,
            defaultAdminRoleHolder: owner,
            depositWhitelistSetRoleHolder: owner,
            depositorWhitelistRoleHolder: owner,
            isDepositLimitSetRoleHolder: owner,
            depositLimitSetRoleHolder: owner
        });

        bytes memory slasherParams =
            abi.encode(ISlasher.InitParams({baseParams: IBaseSlasher.BaseParams({isBurnerHook: false})}));

        (address vaultAddress, address delegatorAddress, address slasherAddress) = vaultConfigurator.create(
            IVaultConfigurator.InitParams({
                version: 1,
                owner: owner,
                vaultParams: abi.encode(baseParams),
                delegatorIndex: delegatorIndex,
                delegatorParams: _legacyDelegatorParams(delegatorIndex),
                withSlasher: true,
                slasherIndex: 0,
                slasherParams: slasherParams
            })
        );

        return (IVaultV2(vaultAddress), delegatorAddress, slasherAddress);
    }

    function _legacyDelegatorParams(uint64 delegatorIndex) internal view returns (bytes memory) {
        IBaseDelegator.BaseParams memory baseParams =
            IBaseDelegator.BaseParams({defaultAdminRoleHolder: owner, hook: address(0), hookSetRoleHolder: address(0)});
        address[] memory roleHolders = new address[](1);
        roleHolders[0] = owner;

        if (delegatorIndex == 0) {
            return abi.encode(
                INetworkRestakeDelegator.InitParams({
                    baseParams: baseParams,
                    networkLimitSetRoleHolders: roleHolders,
                    operatorNetworkSharesSetRoleHolders: roleHolders
                })
            );
        }

        if (delegatorIndex == 1) {
            return abi.encode(
                IFullRestakeDelegator.InitParams({
                    baseParams: baseParams,
                    networkLimitSetRoleHolders: roleHolders,
                    operatorNetworkLimitSetRoleHolders: roleHolders
                })
            );
        }

        if (delegatorIndex == 2) {
            return abi.encode(
                IOperatorSpecificDelegator.InitParams({
                    baseParams: baseParams, networkLimitSetRoleHolders: roleHolders, operator: operator
                })
            );
        }

        if (delegatorIndex == 3) {
            return abi.encode(
                IOperatorNetworkSpecificDelegator.InitParams({
                    baseParams: baseParams, network: network, operator: operator
                })
            );
        }

        revert("UnknownDelegatorIndex");
    }

    function _buildMigrateParams() internal view returns (IVaultV2.MigrateParams memory) {
        uint48 vetoDuration = EPOCH_DURATION > 1 ? 1 : 0;
        IUniversalDelegator.InitParams memory delegatorParams = IUniversalDelegator.InitParams({
            defaultAdminRoleHolder: owner,
            hook: address(0),
            hookSetRoleHolder: owner,
            createSlotRoleHolder: owner,
            setIsSharedRoleHolder: owner,
            setSizeRoleHolder: owner,
            setShareRoleHolder: owner,
            swapSlotsRoleHolder: owner,
            withdrawalBufferSize: type(uint128).max
        });
        IUniversalSlasher.InitParams memory slasherParams = IUniversalSlasher.InitParams({
            isBurnerHook: false, vetoDuration: vetoDuration, resolverSetDelay: EPOCH_DURATION * 3
        });
        return IVaultV2.MigrateParams({
            name: VAULT_NAME,
            symbol: VAULT_SYMBOL,
            delegatorParams: abi.encode(delegatorParams),
            slasherParams: abi.encode(slasherParams)
        });
    }

    function _assertDelegatorMigration(IVaultV2 vault_, address oldDelegator, uint64 legacyType) internal view {
        assertEq(IMigratableEntity(address(vault_)).version(), vaultFactory.lastVersion());
        assertEq(IEntity(oldDelegator).TYPE(), legacyType);

        address newDelegator = vault_.delegator();
        assertTrue(newDelegator != oldDelegator);
        assertEq(IEntity(newDelegator).TYPE(), delegatorFactory.totalTypes() - 1);

        uint208 pending = IUniversalDelegator(newDelegator).getSlot(0).childrenPendingCumulative;
        assertEq(pending, type(uint128).max);
    }
}
