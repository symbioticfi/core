// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

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
import {
    IOperatorNetworkSpecificDelegator,
    OPERATOR_NETWORK_SPECIFIC_DELEGATOR_TYPE
} from "../../src/interfaces/delegator/IOperatorNetworkSpecificDelegator.sol";
import {IOperatorSpecificDelegator} from "../../src/interfaces/delegator/IOperatorSpecificDelegator.sol";
import {
    IUniversalDelegator,
    CREATE_SLOT_ROLE,
    HOOK_GAS_LIMIT,
    HOOK_RESERVE,
    HOOK_SET_ROLE,
    MAX_SUBVAULTS,
    MAX_NETWORKS,
    MAX_OPERATORS,
    SET_WITHDRAWAL_BUFFER_SIZE_ROLE,
    SET_SIZE_ROLE,
    SWAP_SLOTS_ROLE,
    REMOVE_SLOT_ROLE,
    UNIVERSAL_DELEGATOR_TYPE
} from "../../src/interfaces/delegator/IUniversalDelegator.sol";
import {IDelegatorHook} from "../../src/interfaces/delegator/IDelegatorHookV2.sol";
import {IUniversalSlasher} from "../../src/interfaces/slasher/IUniversalSlasher.sol";
import {IEntity} from "../../src/interfaces/common/IEntity.sol";
import {IMigratableEntity} from "../../src/interfaces/common/IMigratableEntity.sol";
import {IVault} from "../../src/interfaces/vault/IVault.sol";
import {IVaultV2} from "../../src/interfaces/vault/IVaultV2.sol";
import {IVaultConfigurator} from "../../src/interfaces/IVaultConfigurator.sol";

import {Token} from "../mocks/Token.sol";
import {MockRewards} from "../mocks/MockRewards.sol";
import {CoreV2StakeForInvariantHelper} from "../helpers/CoreV2StakeForInvariantHelper.sol";

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

contract MockLegacyDelegatorType {
    uint64 public immutable TYPE;

    constructor(uint64 type_) {
        TYPE = type_;
    }
}

contract UniversalDelegatorCoverageHarness is UniversalDelegator {
    using Checkpoints for Checkpoints.Trace208;

    constructor() UniversalDelegator(address(0), address(0), address(0), 0, address(0)) {}

    function setSlotExistsRaw(uint96 index, bool exists_) external {
        slots[index].exists = exists_;
    }

    function setParentChildrenRaw(
        uint96 parentIndex,
        uint32 firstChild,
        uint32 lastChild,
        uint32 totalChildren,
        uint32 existChildren
    ) external {
        slots[parentIndex].firstChild.push(uint48(block.timestamp), firstChild);
        slots[parentIndex].lastChild.push(uint48(block.timestamp), lastChild);
        slots[parentIndex].totalChildren = totalChildren;
        slots[parentIndex].existChildren = existChildren;
    }

    function setSlotLinksRaw(uint96 index, uint32 prevSlot, uint32 nextSlot) external {
        slots[index].prevSlot = prevSlot;
        slots[index].nextSlot.push(uint48(block.timestamp), nextSlot);
    }

    function pushSizeRaw(uint96 index, uint48 key, uint208 size) external {
        slots[index].size.push(key, size);
    }

    function exposeSlotExists(uint96 index) external slotExists(index) {}
}

contract UniversalDelegatorTest is Test, CoreV2StakeForInvariantHelper {
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

    struct StakeTimelineSnapshot {
        uint48 timestamp;
        uint256 activeStake;
        uint256 activeWithdrawals0;
        uint256 activeWithdrawals1;
        uint256 activeWithdrawalsEpoch;
        uint256 stakeFor0;
        uint256 stakeFor1;
        uint256 stakeForMaxDuration;
        uint256 stakeForEpoch;
    }

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
            new VaultV2(
                address(delegatorFactory), address(slasherFactory), address(vaultFactory), address(rewards), address(0)
            )
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
                        depositorToWhitelist: address(0xBEEF),
                        isDepositLimit: false,
                        depositLimit: 0,
                        defaultAdminRoleHolder: owner,
                        depositWhitelistSetRoleHolder: address(0),
                        depositorWhitelistRoleHolder: address(0),
                        isDepositLimitSetRoleHolder: address(0),
                        depositLimitSetRoleHolder: address(0),
                        setPluginLimitRoleHolder: address(0),
                        allocatePluginRoleHolder: address(0)
                    })
                ),
                delegatorIndex: uint64(delegatorFactory.totalTypes() - 1),
                delegatorParams: abi.encode(
                    IUniversalDelegator.InitParams({
                        defaultAdminRoleHolder: owner,
                        hook: address(0),
                        hookSetRoleHolder: address(0),
                        createSlotRoleHolder: owner,
                        setSizeRoleHolder: owner,
                        swapSlotsRoleHolder: owner,
                        withdrawalBufferSize: type(uint128).max
                    })
                ),
                withSlasher: true,
                slasherIndex: uint64(slasherFactory.totalTypes() - 1),
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
        assertEq(delegator.getAllocatedAt(slot1, 0, 5), 30);

        vm.warp(7);
        delegator.setSize(slot1, 20);
        assertEq(delegator.getAllocatedAt(slot1, 0, 7), 30);
        assertEq(delegator.getAllocatedAt(slot1, EPOCH_DURATION - 1, 9), 20);
        assertEq(delegator.getAllocatedAt(slot1, EPOCH_DURATION, 9), 0);
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

        assertEq(delegator.getAllocatedAt(slot1, 0, 1), 45);
        assertEq(delegator.getAllocatedAt(slot2, 0, 1), 50);
        assertEq(_unallocated2(0, slot1, slot2), 5);
    }

    function test_increaseLimit_revertsWhenFullyAllocatedNonLast_withoutUnallocated() public {
        _deposit(alice, 100);

        _createSlot(0, false, 60);
        _createSlot(0, false, 60);

        uint96 slot1 = _rootIndex(uint32(1));
        uint96 slot2 = _rootIndex(uint32(2));

        vm.expectRevert(IUniversalDelegator.NotEnoughBalance.selector);
        delegator.setSize(slot1, 80);
    }

    function test_increaseLimit_allowsWhenNotLastChild_ifLaterSiblingsHaveNoCurrentAllocation() public {
        _deposit(alice, 100);

        _createSlot(0, false, 60);
        _createSlot(0, false, 60);
        _createSlot(0, false, 60);

        uint96 slot1 = _rootIndex(uint32(1));
        uint96 slot2 = _rootIndex(uint32(2));
        uint96 slot3 = _rootIndex(uint32(3));

        assertEq(delegator.getAllocated(slot1, 0), 60);
        assertEq(delegator.getAllocated(slot2, 0), 40);
        assertEq(delegator.getAllocated(slot3, 0), 0);

        delegator.setSize(slot2, 80);

        assertEq(delegator.getAllocated(slot1, 0), 60);
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
        assertEq(delegator.getAllocated(slot1, 0), 60);
        assertEq(delegator.getAllocated(slot2, 0), 30);
        assertEq(_unallocated2(0, slot1, slot2), 10);

        vm.warp(4);
        assertEq(delegator.getAllocated(slot1, 0), 40);
        assertEq(delegator.getAllocated(slot2, 0), 30);
        assertEq(_unallocated2(0, slot1, slot2), 30);
    }

    function test_childrenPending_respectsAllocationWhenResizingChildren() public {
        _deposit(alice, 555);

        _createSlot(0, false, 555);
        uint96 subvault = _rootIndex(uint32(1));

        _createSlot(subvault, false, 444);
        uint96 networkSlot = subvault.createIndex(uint32(1));

        _createSlot(networkSlot, false, 444);
        uint96 operatorSlot = networkSlot.createIndex(uint32(1));

        assertEq(delegator.getAllocated(subvault, 0), 555);
        assertEq(delegator.getAllocated(networkSlot, 0), 444);
        assertEq(delegator.getAllocated(operatorSlot, 0), 444);

        vm.warp(1);
        delegator.setSize(networkSlot, 222);

        assertEq(delegator.getPending(networkSlot, 0), 222);
        assertEq(delegator.getAllocated(networkSlot, 0), 444);
        assertEq(delegator.getAllocated(operatorSlot, 0), 444);

        vm.warp(2);
        delegator.setSize(operatorSlot, 222);

        assertEq(delegator.getPending(operatorSlot, 0), 222);
        assertEq(delegator.getAllocated(operatorSlot, 0), 444);
    }

    function test_childrenPending_accumulatesOnRepeatedOperatorDecrease() public {
        _deposit(alice, 555);

        _createSlot(0, false, 555);
        uint96 subvault = _rootIndex(uint32(1));

        _createSlot(subvault, false, 444);
        uint96 networkSlot = subvault.createIndex(uint32(1));

        _createSlot(networkSlot, false, 444);
        uint96 operatorSlot = networkSlot.createIndex(uint32(1));

        vm.warp(1);
        delegator.setSize(operatorSlot, 222);

        assertEq(delegator.getPending(operatorSlot, 0), 222);
        assertEq(delegator.getAllocated(operatorSlot, 0), 444);

        vm.warp(2);
        delegator.setSize(operatorSlot, 0);

        assertEq(delegator.getPending(operatorSlot, 0), 444);
        assertEq(delegator.getAllocated(networkSlot, 0), 444);
        assertEq(delegator.getAllocated(operatorSlot, 0), 444);
    }

    function test_getAvailableAt_pendingHints_matchNoHintPath() public {
        _deposit(alice, 555);

        _createSlot(0, false, 555);
        uint96 subvault = _rootIndex(uint32(1));

        bytes32 subnetwork = makeAddr("hints-subnetwork").subnetwork(0);
        _createNetworkSlot(subvault, subnetwork, 444);
        uint96 networkSlot = subvault.createIndex(uint32(1));

        _createOperatorSlot(networkSlot, alice, 444);
        uint96 operatorSlot = networkSlot.createIndex(uint32(1));

        vm.warp(1);
        delegator.setSize(operatorSlot, 222);

        vm.warp(2);
        delegator.setSize(operatorSlot, 0);

        uint48 timestampBeforeSlash = uint48(block.timestamp);
        uint208 pendingBefore = delegator.getPendingAt(operatorSlot, 0, timestampBeforeSlash);
        uint256 balanceBefore = delegator.getBalanceAt(networkSlot, 0, timestampBeforeSlash);
        uint256 allocatedBefore = delegator.getAllocatedAt(operatorSlot, 0, timestampBeforeSlash);
        assertGt(pendingBefore, 0);

        vm.prank(address(slasher));
        delegator.onSlash(subnetwork, alice, 20, bytes(""));
        uint48 timestampAfterSlash = uint48(block.timestamp);
        uint208 pendingAfter = delegator.getPendingAt(operatorSlot, 0, timestampAfterSlash);
        uint256 balanceAfter = delegator.getBalanceAt(networkSlot, 0, timestampAfterSlash);
        uint256 allocatedAfter = delegator.getAllocatedAt(operatorSlot, 0, timestampAfterSlash);

        assertLe(pendingAfter, pendingBefore);
        assertLe(balanceAfter, balanceBefore);
        assertLe(allocatedAfter, allocatedBefore);
    }

    function test_pendingWindow_afterSlash_keepsRecentPendingWhenOldPendingExpires() public {
        bytes32 subnetwork = makeAddr("issue5-window-network").subnetwork(0);

        _deposit(alice, 200);
        _createSlot(0, false, MAX_AMOUNT);
        uint96 subvault = _rootIndex(uint32(1));
        _createNetworkSlot(subvault, subnetwork, 200);
        uint96 networkSlot = subvault.createIndex(uint32(1));
        _createOperatorSlot(networkSlot, alice, 200);
        uint96 operatorSlot = networkSlot.createIndex(uint32(1));

        vm.warp(1);
        delegator.setSize(operatorSlot, 100);
        vm.warp(2);
        delegator.setSize(operatorSlot, 200);
        vm.warp(3);
        delegator.setSize(operatorSlot, 70);

        assertEq(delegator.getPending(operatorSlot, 0), 130);

        vm.prank(address(slasher));
        delegator.onSlash(subnetwork, alice, 100, bytes(""));

        assertEq(delegator.getPending(operatorSlot, 0), 30);

        vm.warp(4);
        assertEq(delegator.getPending(operatorSlot, 0), 30);
    }

    function test_noPluginsPendingWindow_afterSlash_keepsRecentPendingWhenOldPendingExpires() public {
        bytes32 subnetwork = makeAddr("issue5-no-plugins-network").subnetwork(0);

        _deposit(alice, 200);

        uint96 noPluginsSubvault = delegator.createSlot(bytes32(0), 0, false, true, 100);
        uint96 networkSlot = delegator.createSlot(subnetwork, noPluginsSubvault, false, false, 100);
        delegator.createSlot(_operatorKey(alice), networkSlot, false, false, 100);

        vm.warp(1);
        delegator.setSize(noPluginsSubvault, 0);
        vm.warp(2);
        delegator.setSize(noPluginsSubvault, 100);
        vm.warp(3);
        delegator.setSize(noPluginsSubvault, 70);

        assertEq(delegator.getPending(noPluginsSubvault, 0), 130);
        assertEq(delegator.getNoPluginsSize(), 200);

        vm.prank(address(slasher));
        delegator.onSlash(subnetwork, alice, 100, bytes(""));

        assertEq(delegator.getPending(noPluginsSubvault, 0), 30);
        assertEq(delegator.getNoPluginsSize(), 100);

        vm.warp(4);
        assertEq(delegator.getPending(noPluginsSubvault, 0), 30);
        assertEq(delegator.getNoPluginsSize(), 100);
    }

    function test_sharedSubvault_allowsNetworkRestaking_betweenDepth2Siblings() public {
        _deposit(alice, 100);

        _createSlot(0, true, 100);
        uint96 subvault = _rootIndex(uint32(1));

        _createSlot(subvault, false, 80);
        _createSlot(subvault, false, 80);
        uint96 net1 = subvault.createIndex(uint32(1));
        uint96 net2 = subvault.createIndex(uint32(2));

        assertEq(delegator.getAllocated(subvault, 0), 100);
        assertEq(delegator.getAllocated(net1, 0), 80);
        assertEq(delegator.getAllocated(net2, 0), 80);
    }

    function test_sharedSubvault_networkPrevSumsStayZero() public {
        _deposit(alice, 200);

        _createSlot(0, true, 200);
        uint96 subvault = _rootIndex(uint32(1));

        _createSlot(subvault, false, 120);
        _createSlot(subvault, false, 80);
        uint96 net1 = subvault.createIndex(uint32(1));
        uint96 net2 = subvault.createIndex(uint32(2));

        assertEq(delegator.getSlot(net1).prevSizeSum, 0);
        assertEq(delegator.getSlot(net2).prevSizeSum, 0);

        vm.warp(1);
        delegator.setSize(net1, 60);

        assertEq(delegator.getSlot(net1).prevSizeSum, 0);
        assertEq(delegator.getSlot(net2).prevSizeSum, 0);
    }

    function test_sharedSubvault_setSizeDecreaseKeepsRequestedSlashExecutable() public {
        address network = makeAddr("issue23-network");
        address middleware = makeAddr("issue23-middleware");
        address operator = alice;
        _registerNetwork(network, middleware);
        _registerOperator(operator);
        _optIn(operator, network);

        bytes32 subnetwork = network.subnetwork(0);
        vm.prank(network);
        delegator.setMaxNetworkLimit(0, type(uint256).max);

        _createSlot(0, true, 100);
        uint96 subvault = _rootIndex(uint32(1));
        _createNetworkSlot(subvault, subnetwork, 100);
        uint96 networkSlot = subvault.createIndex(uint32(1));
        _createOperatorSlot(networkSlot, operator, 100);

        _deposit(operator, 100);

        vm.prank(middleware);
        uint256 slashIndex = slasher.requestSlash(subnetwork, operator, 90, 0, "");

        vm.warp(1);
        delegator.setSize(networkSlot, 0);
        assertGt(delegator.getPending(networkSlot, 0), 0);
        assertEq(delegator.getAllocated(networkSlot, 0), 100);
        assertEq(delegator.getAllocated(networkSlot, EPOCH_DURATION), 0);

        vm.prank(middleware);
        assertEq(slasher.executeSlash(slashIndex, ""), 90);
    }

    function test_sharedSubvault_sharedRisk_secondRequestCanBecomeUnexecutable() public {
        address network1 = makeAddr("issue3-network1");
        address network2 = makeAddr("issue3-network2");
        address network3 = makeAddr("issue3-network3");
        address middleware = makeAddr("issue3-middleware");
        address operator3 = makeAddr("issue3-operator3");

        _registerNetwork(network1, middleware);
        _registerNetwork(network2, middleware);
        _registerNetwork(network3, middleware);
        _registerOperator(alice);
        _registerOperator(bob);
        _registerOperator(operator3);
        _optIn(alice, network1);
        _optIn(bob, network2);
        _optIn(operator3, network3);

        bytes32 subnetwork1 = network1.subnetwork(0);
        bytes32 subnetwork2 = network2.subnetwork(0);
        bytes32 subnetwork3 = network3.subnetwork(0);
        vm.prank(network1);
        delegator.setMaxNetworkLimit(0, type(uint256).max);
        vm.prank(network2);
        delegator.setMaxNetworkLimit(0, type(uint256).max);
        vm.prank(network3);
        delegator.setMaxNetworkLimit(0, type(uint256).max);

        _createSlot(0, true, 10);
        _createSlot(0, false, 10);
        uint96 sharedSubvault = _rootIndex(uint32(1));
        uint96 isolatedSubvault = _rootIndex(uint32(2));

        _createNetworkSlot(sharedSubvault, subnetwork1, 10);
        _createNetworkSlot(sharedSubvault, subnetwork2, 10);
        _createOperatorSlot(sharedSubvault.createIndex(uint32(1)), alice, 10);
        _createOperatorSlot(sharedSubvault.createIndex(uint32(2)), bob, 10);

        _createNetworkSlot(isolatedSubvault, subnetwork3, 10);
        _createOperatorSlot(isolatedSubvault.createIndex(uint32(1)), operator3, 10);

        _deposit(alice, 20);
        vm.warp(1);

        assertEq(delegator.stake(subnetwork1, alice), 10);
        assertEq(delegator.stake(subnetwork2, bob), 10);
        assertEq(delegator.stake(subnetwork3, operator3), 10);

        vm.startPrank(middleware);
        uint256 slashIndex1 = slasher.requestSlash(subnetwork1, alice, 10, 0, "");
        uint256 slashIndex2 = slasher.requestSlash(subnetwork2, bob, 10, 0, "");
        assertEq(slasher.executeSlash(slashIndex1, ""), 10);
        vm.stopPrank();

        // Shared-risk model: a slash in one network shrinks the shared parent and affects sibling stake.
        assertEq(delegator.stake(subnetwork1, alice), 0);
        assertEq(delegator.stake(subnetwork2, bob), 0);
        assertEq(delegator.stake(subnetwork3, operator3), 10);

        vm.prank(middleware);
        vm.expectRevert(IUniversalSlasher.InsufficientSlash.selector);
        slasher.executeSlash(slashIndex2, "");

        assertEq(delegator.stake(subnetwork3, operator3), 10);
    }

    function test_depth3Operators_areIsolatedWithinNetwork() public {
        _deposit(alice, 100);

        _createSlot(0, true, 100);
        uint96 subvault = _rootIndex(uint32(1));

        _createSlot(subvault, false, 80);
        uint96 net1 = subvault.createIndex(uint32(1));

        _createSlot(net1, false, 50);
        _createSlot(net1, false, 50);
        uint96 op1 = net1.createIndex(uint32(1));
        uint96 op2 = net1.createIndex(uint32(2));

        assertEq(delegator.getAllocated(net1, 0), 80);
        assertEq(delegator.getAllocated(op1, 0), 50);
        assertEq(delegator.getAllocated(op2, 0), 30);
    }

    function test_getFilled_zeroWhenNetworkHasNoOperators() public {
        _deposit(alice, 100);

        _createSlot(0, false, MAX_AMOUNT);
        uint96 subvault = _rootIndex(uint32(1));

        _createSlot(subvault, false, 100);
        uint96 networkSlot = subvault.createIndex(uint32(1));

        assertEq(delegator.getFilled(networkSlot, 0), 0);
    }

    function test_getFilled_matchesSumOfOperatorsForNetwork() public {
        _deposit(alice, 100);

        _createSlot(0, false, MAX_AMOUNT);
        uint96 subvault = _rootIndex(uint32(1));

        _createSlot(subvault, false, 100);
        uint96 networkSlot = subvault.createIndex(uint32(1));

        _createSlot(networkSlot, false, 70);
        _createSlot(networkSlot, false, 70);
        uint96 op1 = networkSlot.createIndex(uint32(1));
        uint96 op2 = networkSlot.createIndex(uint32(2));

        uint256 expected = delegator.getAllocated(op1, 0) + delegator.getAllocated(op2, 0);
        assertEq(delegator.getFilled(networkSlot, 0), expected);
        assertEq(delegator.getFilled(networkSlot, 0), 100);
    }

    function test_getFilled_respectsDurationWindowForPending() public {
        _deposit(alice, 200);

        _createSlot(0, false, MAX_AMOUNT);
        uint96 subvault = _rootIndex(uint32(1));

        _createSlot(subvault, false, 200);
        uint96 networkSlot = subvault.createIndex(uint32(1));

        _createSlot(networkSlot, false, 100);
        _createSlot(networkSlot, false, 100);
        uint96 op1 = networkSlot.createIndex(uint32(1));
        uint96 op2 = networkSlot.createIndex(uint32(2));

        vm.warp(1);
        delegator.setSize(op1, 50);

        vm.warp(2);
        uint48 maxDuration = EPOCH_DURATION - 1;
        uint256 expectedWithPendingWindow = delegator.getAllocated(op1, 0) + delegator.getAllocated(op2, 0);
        uint256 expectedWithMaxDurationWindow =
            delegator.getAllocated(op1, maxDuration) + delegator.getAllocated(op2, maxDuration);

        assertEq(expectedWithPendingWindow, 200);
        assertEq(expectedWithMaxDurationWindow, 150);
        assertEq(delegator.getFilled(networkSlot, 0), expectedWithPendingWindow);
        assertEq(delegator.getFilled(networkSlot, maxDuration), expectedWithMaxDurationWindow);
        assertEq(delegator.getFilled(networkSlot, EPOCH_DURATION), 0);
        assertEq(delegator.getFilled(networkSlot, 0), 200);
        assertEq(delegator.getFilled(networkSlot, maxDuration), 150);
    }

    function test_getFilled_numericTrace_multiDepthMultipleSizeChanges() public {
        _deposit(alice, 1000);

        _createSlot(0, false, 700);
        _createSlot(0, false, 500);
        uint96 subvault1 = _rootIndex(uint32(1));
        uint96 subvault2 = _rootIndex(uint32(2));

        _createSlot(subvault1, false, 500);
        _createSlot(subvault1, false, 300);
        uint96 network1 = subvault1.createIndex(uint32(1));
        uint96 network2 = subvault1.createIndex(uint32(2));

        _createSlot(network1, false, 220);
        _createSlot(network1, false, 180);
        _createSlot(network1, false, 160);
        uint96 op1 = network1.createIndex(uint32(1));
        uint96 op2 = network1.createIndex(uint32(2));
        uint96 op3 = network1.createIndex(uint32(3));

        // Initial state.
        assertEq(delegator.getAllocated(subvault1, 0), 700);
        assertEq(delegator.getAllocated(subvault2, 0), 300);
        assertEq(delegator.getAllocated(network1, 0), 500);
        assertEq(delegator.getAllocated(network2, 0), 200);
        assertEq(delegator.getAllocated(op1, 0), 220);
        assertEq(delegator.getAllocated(op2, 0), 180);
        assertEq(delegator.getAllocated(op3, 0), 100);
        assertEq(
            delegator.getAllocated(op1, 0) + delegator.getAllocated(op2, 0) + delegator.getAllocated(op3, 0),
            delegator.getFilled(network1, 0)
        );
        assertEq(delegator.getFilled(network1, 0), 500);

        // Decrease network size: allocation stays 500 due to pending=80.
        vm.warp(1);
        delegator.setSize(network1, 420);
        assertEq(delegator.getPending(network1, 0), 80);
        assertEq(delegator.getAllocated(network1, 0), 500);
        assertEq(delegator.getAllocated(network2, 0), 200);
        assertEq(delegator.getFilled(network1, 0), 500);

        // Decrease operator2 size: creates pending=60 for operator2/network1.
        vm.warp(2);
        delegator.setSize(op2, 120);
        assertEq(delegator.getPending(op2, 0), 60);
        assertEq(delegator.getAllocated(op1, 0), 220);
        assertEq(delegator.getAllocated(op2, 0), 180);
        assertEq(delegator.getAllocated(op3, 0), 100);
        assertEq(
            delegator.getAllocated(op1, 0) + delegator.getAllocated(op2, 0) + delegator.getAllocated(op3, 0),
            delegator.getFilled(network1, 0)
        );
        assertEq(delegator.getFilled(network1, 0), 500);

        // Decrease operator3 size from 160 -> 100: pending remains 0 (allocated was already 100).
        vm.warp(3);
        delegator.setSize(op3, 100);
        assertEq(delegator.getPending(op3, 0), 0);
        assertEq(delegator.getAllocated(op3, 0), 100);

        // Attempting operator1 increase 220 -> 260 reverts in this state (no tail unallocated amount).
        vm.warp(4);
        vm.expectRevert(IUniversalDelegator.NotEnoughBalance.selector);
        delegator.setSize(op1, 260);

        // After pending windows expire, the same topology has lower filled amount.
        vm.warp(6);
        assertEq(delegator.getPending(network1, 0), 0);
        assertEq(delegator.getPending(op2, 0), 0);
        assertEq(delegator.getAllocated(network1, 0), 420);
        assertEq(delegator.getAllocated(op1, 0), 220);
        assertEq(delegator.getAllocated(op2, 0), 120);
        assertEq(delegator.getAllocated(op3, 0), 80);
        assertEq(
            delegator.getAllocated(op1, 0) + delegator.getAllocated(op2, 0) + delegator.getAllocated(op3, 0),
            delegator.getFilled(network1, 0)
        );
        assertEq(delegator.getFilled(network1, 0), 420);
    }

    function test_getFilled_invariant_repeatedSetSizes_withDepositWithdraw() public {
        _deposit(alice, 400);

        _createSlot(0, false, MAX_AMOUNT);
        uint96 subvault = _rootIndex(uint32(1));
        _createSlot(subvault, false, 400);
        uint96 networkSlot = subvault.createIndex(uint32(1));

        _createSlot(networkSlot, false, 200);
        _createSlot(networkSlot, false, 150);
        _createSlot(networkSlot, false, 150);
        uint96 op1 = networkSlot.createIndex(uint32(1));
        uint96 op2 = networkSlot.createIndex(uint32(2));
        uint96 op3 = networkSlot.createIndex(uint32(3));

        uint256 sumInitial =
            delegator.getAllocated(op1, 0) + delegator.getAllocated(op2, 0) + delegator.getAllocated(op3, 0);
        assertEq(sumInitial, 400);
        assertEq(delegator.getFilled(networkSlot, 0), sumInitial);
        assertEq(delegator.getFilled(networkSlot, 0), 400);

        vm.warp(1);
        delegator.setSize(op2, 120);
        assertEq(delegator.getPending(op2, 0), 30);
        assertEq(
            delegator.getFilled(networkSlot, 0),
            delegator.getAllocated(op1, 0) + delegator.getAllocated(op2, 0) + delegator.getAllocated(op3, 0)
        );
        assertEq(delegator.getFilled(networkSlot, 0), 400);

        vm.warp(2);
        delegator.setSize(op1, 170);
        assertEq(delegator.getPending(op1, 0), 30);
        assertEq(delegator.getPending(op1, 0) + delegator.getPending(op2, 0) + delegator.getPending(op3, 0), 60);

        uint48 maxDuration = EPOCH_DURATION - 1;
        uint256 filledWithPending = delegator.getFilled(networkSlot, 0);
        uint256 filledMaxDuration = delegator.getFilled(networkSlot, maxDuration);
        assertEq(
            filledWithPending,
            delegator.getAllocated(op1, 0) + delegator.getAllocated(op2, 0) + delegator.getAllocated(op3, 0)
        );
        assertEq(
            filledMaxDuration,
            delegator.getAllocated(op1, maxDuration) + delegator.getAllocated(op2, maxDuration)
                + delegator.getAllocated(op3, maxDuration)
        );
        assertGe(filledWithPending, filledMaxDuration);
        assertEq(filledWithPending, 400);
        assertEq(filledMaxDuration, 370);
        assertEq(delegator.getFilled(networkSlot, EPOCH_DURATION), 0);

        vm.warp(3);
        _withdraw(alice, 100);
        _deposit(bob, 80);
        assertEq(
            delegator.getFilled(networkSlot, 0),
            delegator.getAllocated(op1, 0) + delegator.getAllocated(op2, 0) + delegator.getAllocated(op3, 0)
        );
        assertEq(delegator.getFilled(networkSlot, 0), 400);

        vm.warp(EPOCH_DURATION + 4);
        assertEq(delegator.getPending(op1, 0), 0);
        assertEq(delegator.getPending(op2, 0), 0);
        assertEq(
            delegator.getFilled(networkSlot, 0),
            delegator.getAllocated(op1, 0) + delegator.getAllocated(op2, 0) + delegator.getAllocated(op3, 0)
        );
        assertEq(delegator.getFilled(networkSlot, 0), 380);
        assertEq(delegator.getFilled(networkSlot, 0), delegator.getFilled(networkSlot, maxDuration));
        assertEq(delegator.getFilled(networkSlot, maxDuration), 380);
        assertEq(delegator.getFilled(networkSlot, EPOCH_DURATION), 0);
    }

    function test_getFilled_invariant_afterSwapsResizesAndStakeChanges() public {
        _deposit(alice, 300);

        _createSlot(0, false, MAX_AMOUNT);
        uint96 subvault = _rootIndex(uint32(1));
        _createSlot(subvault, false, 300);
        uint96 networkSlot = subvault.createIndex(uint32(1));

        _createSlot(networkSlot, false, 100);
        _createSlot(networkSlot, false, 100);
        _createSlot(networkSlot, false, 100);
        uint96 op1 = networkSlot.createIndex(uint32(1));
        uint96 op2 = networkSlot.createIndex(uint32(2));
        uint96 op3 = networkSlot.createIndex(uint32(3));

        assertEq(delegator.getFilled(networkSlot, 0), 300);
        assertEq(
            delegator.getFilled(networkSlot, 0),
            delegator.getAllocated(op1, 0) + delegator.getAllocated(op2, 0) + delegator.getAllocated(op3, 0)
        );
        assertEq(delegator.getFilled(networkSlot, 0), 300);

        vm.warp(1);
        delegator.swapSlots(op1, op3);
        assertEq(
            delegator.getFilled(networkSlot, 0),
            delegator.getAllocated(op1, 0) + delegator.getAllocated(op2, 0) + delegator.getAllocated(op3, 0)
        );
        assertEq(delegator.getFilled(networkSlot, 0), 300);

        vm.warp(2);
        delegator.setSize(op3, 70);
        assertEq(delegator.getPending(op3, 0), 30);
        assertEq(
            delegator.getFilled(networkSlot, 0),
            delegator.getAllocated(op1, 0) + delegator.getAllocated(op2, 0) + delegator.getAllocated(op3, 0)
        );
        assertEq(delegator.getFilled(networkSlot, 0), 300);

        vm.warp(3);
        delegator.swapSlots(op3, op2);
        assertEq(
            delegator.getFilled(networkSlot, 0),
            delegator.getAllocated(op1, 0) + delegator.getAllocated(op2, 0) + delegator.getAllocated(op3, 0)
        );
        assertEq(delegator.getFilled(networkSlot, 0), 300);

        vm.warp(4);
        _withdraw(alice, 120);
        _deposit(bob, 50);
        assertEq(
            delegator.getFilled(networkSlot, 0),
            delegator.getAllocated(op1, 0) + delegator.getAllocated(op2, 0) + delegator.getAllocated(op3, 0)
        );
        assertEq(delegator.getFilled(networkSlot, 0), 300);

        vm.warp(EPOCH_DURATION + 5);
        assertEq(delegator.getPending(op3, 0), 0);
        assertEq(
            delegator.getFilled(networkSlot, 0),
            delegator.getAllocated(op1, 0) + delegator.getAllocated(op2, 0) + delegator.getAllocated(op3, 0)
        );
        assertEq(delegator.getFilled(networkSlot, 0), 230);
        uint48 maxDuration = EPOCH_DURATION - 1;
        assertEq(delegator.getFilled(networkSlot, 0), delegator.getFilled(networkSlot, maxDuration));
        assertEq(delegator.getFilled(networkSlot, maxDuration), 230);
        assertEq(delegator.getFilled(networkSlot, EPOCH_DURATION), 0);
    }

    struct Test_GetFilledInvariantAfterSlashingResetRemovalStruct {
        address network1;
        address network2;
        address middleware;
        address operator1;
        address operator2;
        address operator3;
        address extraOperator;
        bytes32 subnetwork1;
        bytes32 subnetwork2;
        uint96 subvault;
        uint96 networkSlot1;
        uint96 networkSlot2;
        uint96 opSlot1;
        uint96 opSlot2;
        uint96 opSlot3;
        uint96 extraSlot;
        uint256 slashIndex;
        uint256 slashedAmount;
    }

    function test_getFilled_invariant_afterSlashingResetRemovalAndStakeChanges() public {
        Test_GetFilledInvariantAfterSlashingResetRemovalStruct memory testStruct;
        testStruct.network1 = makeAddr("filled-network-1");
        testStruct.network2 = makeAddr("filled-network-2");
        testStruct.middleware = makeAddr("filled-middleware");
        testStruct.operator1 = alice;
        testStruct.operator2 = bob;
        testStruct.operator3 = makeAddr("filled-operator-3");
        testStruct.extraOperator = makeAddr("filled-extra-operator");

        _registerNetwork(testStruct.network1, testStruct.middleware);
        _registerNetwork(testStruct.network2, testStruct.middleware);
        _registerOperator(testStruct.operator1);
        _registerOperator(testStruct.operator2);
        _registerOperator(testStruct.operator3);
        _registerOperator(testStruct.extraOperator);
        _optIn(testStruct.operator1, testStruct.network1);
        _optIn(testStruct.operator2, testStruct.network1);
        _optIn(testStruct.operator3, testStruct.network2);

        testStruct.subnetwork1 = testStruct.network1.subnetwork(0);
        testStruct.subnetwork2 = testStruct.network2.subnetwork(0);
        vm.prank(testStruct.network1);
        delegator.setMaxNetworkLimit(0, type(uint256).max);
        vm.prank(testStruct.network2);
        delegator.setMaxNetworkLimit(0, type(uint256).max);

        _deposit(alice, 500);

        _createSlot(0, false, MAX_AMOUNT);
        testStruct.subvault = _rootIndex(uint32(1));
        _createNetworkSlot(testStruct.subvault, testStruct.subnetwork1, 300);
        _createNetworkSlot(testStruct.subvault, testStruct.subnetwork2, 200);
        testStruct.networkSlot1 = testStruct.subvault.createIndex(uint32(1));
        testStruct.networkSlot2 = testStruct.subvault.createIndex(uint32(2));

        _createOperatorSlot(testStruct.networkSlot1, testStruct.operator1, 180);
        _createOperatorSlot(testStruct.networkSlot1, testStruct.operator2, 180);
        testStruct.opSlot1 = testStruct.networkSlot1.createIndex(uint32(1));
        testStruct.opSlot2 = testStruct.networkSlot1.createIndex(uint32(2));

        _createOperatorSlot(testStruct.networkSlot2, testStruct.operator3, 200);
        testStruct.opSlot3 = testStruct.networkSlot2.createIndex(uint32(1));

        assertEq(
            delegator.getFilled(testStruct.networkSlot1, 0),
            delegator.getAllocated(testStruct.opSlot1, 0) + delegator.getAllocated(testStruct.opSlot2, 0)
        );
        assertEq(delegator.getFilled(testStruct.networkSlot2, 0), delegator.getAllocated(testStruct.opSlot3, 0));
        assertEq(delegator.getFilled(testStruct.networkSlot1, 0), 300);
        assertEq(delegator.getFilled(testStruct.networkSlot2, 0), 200);

        vm.warp(1);
        _withdraw(alice, 100);
        _deposit(bob, 40);
        assertEq(delegator.getFilled(testStruct.networkSlot1, 0), 300);
        assertEq(delegator.getFilled(testStruct.networkSlot2, 0), 200);

        vm.startPrank(testStruct.middleware);
        testStruct.slashIndex = slasher.requestSlash(testStruct.subnetwork1, testStruct.operator1, 70, 0, "");
        testStruct.slashedAmount = slasher.executeSlash(testStruct.slashIndex, "");
        vm.stopPrank();
        assertGt(testStruct.slashedAmount, 0);
        assertEq(testStruct.slashedAmount, 70);
        assertEq(
            delegator.getFilled(testStruct.networkSlot1, 0),
            delegator.getAllocated(testStruct.opSlot1, 0) + delegator.getAllocated(testStruct.opSlot2, 0)
        );
        assertEq(delegator.getFilled(testStruct.networkSlot1, 0), 230);

        vm.prank(testStruct.middleware);
        delegator.resetAllocation(testStruct.subnetwork2);
        assertEq(delegator.getSlotOfNetwork(testStruct.subnetwork2), 0);
        assertEq(
            delegator.getFilled(testStruct.networkSlot1, 0),
            delegator.getAllocated(testStruct.opSlot1, 0) + delegator.getAllocated(testStruct.opSlot2, 0)
        );
        assertEq(delegator.getFilled(testStruct.networkSlot1, 0), 230);

        delegator.grantRole(REMOVE_SLOT_ROLE, owner);
        _createOperatorSlot(testStruct.networkSlot1, testStruct.extraOperator, 0);
        testStruct.extraSlot = testStruct.networkSlot1.createIndex(uint32(3));
        delegator.removeSlot(testStruct.extraSlot);
        assertEq(delegator.getSlotOfOperator(testStruct.networkSlot1, testStruct.extraOperator), 0);

        assertEq(
            delegator.getFilled(testStruct.networkSlot1, 0),
            delegator.getAllocated(testStruct.opSlot1, 0) + delegator.getAllocated(testStruct.opSlot2, 0)
        );
        assertEq(delegator.getFilled(testStruct.networkSlot1, 0), 230);
    }

    function test_isolatedSubvaults_prioritizedOverTime() public {
        _createSlot(0, false, 30);
        _createSlot(0, false, 50);
        _createSlot(0, false, 100);

        uint96 slot1 = _rootIndex(uint32(1));
        uint96 slot2 = _rootIndex(uint32(2));
        uint96 slot3 = _rootIndex(uint32(3));

        vm.warp(1);
        _deposit(alice, 60);

        assertEq(delegator.getAllocatedAt(slot1, 0, 1), 30);
        assertEq(delegator.getAllocatedAt(slot2, 0, 1), 30);
        assertEq(delegator.getAllocatedAt(slot3, 0, 1), 0);

        vm.warp(2);
        _deposit(alice, 60);

        assertEq(delegator.getAllocatedAt(slot1, 0, 2), 30);
        assertEq(delegator.getAllocatedAt(slot2, 0, 2), 50);
        assertEq(delegator.getAllocatedAt(slot3, 0, 2), 40);
    }

    function test_isolatedNetworks_followSubvaultPriority() public {
        _deposit(alice, 150);

        _createSlot(0, false, 200);
        uint96 subvault = _rootIndex(uint32(1));

        _createSlot(subvault, false, 60);
        _createSlot(subvault, false, 120);
        uint96 net1 = subvault.createIndex(uint32(1));
        uint96 net2 = subvault.createIndex(uint32(2));

        assertEq(delegator.getAllocated(subvault, 0), 150);
        assertEq(delegator.getAllocated(net1, 0), 60);
        assertEq(delegator.getAllocated(net2, 0), 90);
    }

    function test_isolatedOperators_prioritizedAfterStakeDecrease() public {
        _createSlot(0, false, 1000);
        uint96 subvault = _rootIndex(uint32(1));

        _createSlot(subvault, false, 1000);
        uint96 networkSlot = subvault.createIndex(uint32(1));

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

        assertEq(delegator.getAllocated(slot1, 0), 70);
        assertEq(delegator.getAllocated(slot2, 0), 30);

        vm.warp(1 + EPOCH_DURATION);
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

    struct Test_SharedSubvaultSlashCappedAcrossNetworksSameCaptureTimestampStruct {
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
        uint96 subvault1;
        uint96 subvault2;
        uint96 netSlot1;
        uint96 netSlot2;
        uint96 netSlot3;
        uint96 opSlot1;
        uint96 opSlot2;
        uint96 opSlot3;
        uint48 captureTimestamp;
    }

    function test_sharedSubvault_slashCappedAcrossNetworks_sameCaptureTimestamp() public {
        Test_SharedSubvaultSlashCappedAcrossNetworksSameCaptureTimestampStruct memory testStruct;

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
        vm.prank(testStruct.network1);
        delegator.setMaxNetworkLimit(0, type(uint256).max);
        vm.prank(testStruct.network2);
        delegator.setMaxNetworkLimit(0, type(uint256).max);
        vm.prank(testStruct.network3);
        delegator.setMaxNetworkLimit(0, type(uint256).max);

        _createSlot(0, true, 60);
        _createSlot(0, false, 40);
        testStruct.subvault1 = _rootIndex(uint32(1));
        testStruct.subvault2 = _rootIndex(uint32(2));

        _createNetworkSlot(testStruct.subvault1, testStruct.subnetwork1, 60);
        _createNetworkSlot(testStruct.subvault1, testStruct.subnetwork2, 60);
        testStruct.netSlot1 = testStruct.subvault1.createIndex(uint32(1));
        testStruct.netSlot2 = testStruct.subvault1.createIndex(uint32(2));

        _createOperatorSlot(testStruct.netSlot1, testStruct.operator1, 60);
        testStruct.opSlot1 = testStruct.netSlot1.createIndex(uint32(1));

        _createOperatorSlot(testStruct.netSlot2, testStruct.operator2, 60);
        testStruct.opSlot2 = testStruct.netSlot2.createIndex(uint32(1));

        _createNetworkSlot(testStruct.subvault2, testStruct.subnetwork3, 40);
        testStruct.netSlot3 = testStruct.subvault2.createIndex(uint32(1));

        _createOperatorSlot(testStruct.netSlot3, testStruct.operator3, 40);
        testStruct.opSlot3 = testStruct.netSlot3.createIndex(uint32(1));

        _deposit(testStruct.operator1, 100);

        vm.startPrank(testStruct.middleware);
        assertEq(slasher.requestSlash(testStruct.subnetwork1, testStruct.operator1, 60, 0, ""), 0);
        assertEq(slasher.requestSlash(testStruct.subnetwork2, testStruct.operator2, 60, 0, ""), 1);
        assertEq(slasher.requestSlash(testStruct.subnetwork3, testStruct.operator3, 40, 0, ""), 2);
        vm.stopPrank();
    }

    function test_sharedSubvault_slashCappedAcrossNetworks_differentCaptureTimestamp() public {
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
        vm.prank(network1);
        delegator.setMaxNetworkLimit(0, type(uint256).max);
        vm.prank(network2);
        delegator.setMaxNetworkLimit(0, type(uint256).max);

        _createSlot(0, true, 60);
        uint96 subvault = _rootIndex(uint32(1));

        _createNetworkSlot(subvault, subnetwork1, 60);
        _createNetworkSlot(subvault, subnetwork2, 60);
        uint96 netSlot1 = subvault.createIndex(uint32(1));
        uint96 netSlot2 = subvault.createIndex(uint32(2));

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

    function test_sharedSubvault_slashAllowsNewStake_laterCaptureTimestamp() public {
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
        vm.prank(network1);
        delegator.setMaxNetworkLimit(0, type(uint256).max);
        vm.prank(network2);
        delegator.setMaxNetworkLimit(0, type(uint256).max);

        _createSlot(0, true, 200);
        uint96 subvault = _rootIndex(uint32(1));

        _createNetworkSlot(subvault, subnetwork1, 200);
        _createNetworkSlot(subvault, subnetwork2, 200);
        uint96 netSlot1 = subvault.createIndex(uint32(1));
        uint96 netSlot2 = subvault.createIndex(uint32(2));

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

    function testFuzz_isolatedSubvaults_followPriority(uint256 depositAmount, uint256 size1, uint256 size2) public {
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
        uint96 subvault = _rootIndex(uint32(1));

        _createSlot(subvault, false, MAX_AMOUNT);
        uint96 networkSlot = subvault.createIndex(uint32(1));

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

        uint256 available = delegator.getBalance(0, 0);
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

        uint256 available = delegator.getBalance(0, 0);
        uint256 expected1 = available < cap1 ? available : cap1;
        uint256 remaining = available > cap1 ? available - cap1 : 0;
        uint256 expected2 = remaining < cap2 ? remaining : cap2;

        assertEq(delegator.getAllocated(slot1, 0), expected1);
        assertEq(delegator.getAllocated(slot2, 0), expected2);
    }

    function testFuzz_isolatedShares_doNotOverlapInSubvault(uint256 depositAmount, uint256 size1, uint256 size2)
        public
    {
        uint256 cap1 = bound(size1, 0, MAX_AMOUNT);
        uint256 cap2 = bound(size2, 0, MAX_AMOUNT);
        uint256 amount = bound(depositAmount, 1, MAX_AMOUNT);

        _createSlot(0, false, MAX_AMOUNT);
        uint96 subvault = _rootIndex(uint32(1));

        _createSlot(subvault, false, cap1);
        _createSlot(subvault, false, cap2);
        uint96 slot1 = subvault.createIndex(uint32(1));
        uint96 slot2 = subvault.createIndex(uint32(2));

        _deposit(alice, amount);

        uint256 available = delegator.getBalance(subvault, 0);
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
        uint96 subvault;
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
        testStruct.subvault = _rootIndex(uint32(1));

        testStruct.subnetwork1 = testStruct.network1.subnetwork(0);
        testStruct.subnetwork2 = testStruct.network2.subnetwork(0);
        _createNetworkSlot(testStruct.subvault, testStruct.subnetwork1, testStruct.cap1);
        _createNetworkSlot(testStruct.subvault, testStruct.subnetwork2, testStruct.cap2);
        testStruct.networkSlot1 = testStruct.subvault.createIndex(uint32(1));
        testStruct.networkSlot2 = testStruct.subvault.createIndex(uint32(2));

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
        uint96 subvault;
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
        uint96 subvault = _rootIndex(uint32(1));

        testStruct.subnetwork = testStruct.network.subnetwork(0);
        _createNetworkSlot(subvault, testStruct.subnetwork, networkSize);
        uint96 networkSlot = subvault.createIndex(uint32(1));

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

    function test_isShared_trueWhenSubvaultIsShared() public {
        bytes32 subnetwork = bytes32(uint256(1));

        _deposit(alice, 100);

        _createSlot(0, true, 100);
        uint96 subvault = _rootIndex(uint32(1));

        _createNetworkSlot(subvault, subnetwork, 100);
        uint96 networkSlot = subvault.createIndex(uint32(1));

        _createOperatorSlot(networkSlot, alice, 100);
        uint96 operatorSlot = networkSlot.createIndex(uint32(1));

        assertTrue(delegator.getIsShared(subnetwork));
    }

    function test_isShared_falseWhenSubvaultNotShared() public {
        bytes32 subnetwork = bytes32(uint256(1));

        _deposit(alice, 100);

        _createSlot(0, false, 100);
        uint96 subvault = _rootIndex(uint32(1));

        _createNetworkSlot(subvault, subnetwork, 100);
        uint96 networkSlot = subvault.createIndex(uint32(1));

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

    function test_multicall_executesCallsSequentially() public {
        _deposit(alice, 100);

        delegator.grantRole(SET_WITHDRAWAL_BUFFER_SIZE_ROLE, owner);

        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(UniversalDelegator.setWithdrawalBufferSize, (40));
        calls[1] = abi.encodeCall(UniversalDelegator.setWithdrawalBufferSize, (20));

        delegator.multicall(calls);

        assertEq(delegator.getWithdrawalBuffer(), 20);
    }

    function test_multicall_bubblesRevertReason() public {
        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeCall(UniversalDelegator.setWithdrawalBufferSize, (40));

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, owner, SET_WITHDRAWAL_BUFFER_SIZE_ROLE
            )
        );
        delegator.multicall(calls);
    }

    function test_depthGuards_enforced() public {
        _createSlot(0, false, 100);
        uint96 subvault = _rootIndex(uint32(1));

        _createSlot(subvault, false, 100);

        vm.expectRevert(IUniversalDelegator.WrongDepth.selector);
        _createSlot(subvault, true, 1);
    }

    function test_networkAssignment_duplicateAndUnassignChecks() public {
        bytes32 subnetwork = bytes32(uint256(1));

        _createSlot(0, false, 100);
        uint96 subvault = _rootIndex(uint32(1));

        _createNetworkSlot(subvault, subnetwork, 100);
        uint96 net1 = subvault.createIndex(uint32(1));

        assertEq(delegator.getSlotOfNetwork(subnetwork), net1);

        vm.expectRevert(IUniversalDelegator.AlreadyAssigned.selector);
        _createNetworkSlot(subvault, subnetwork, 100);
    }

    function test_networkAssignment_revertsWhenSlotAlreadyAssigned() public {
        bytes32 subnetwork1 = bytes32(uint256(1));
        bytes32 subnetwork2 = bytes32(uint256(2));

        _createSlot(0, false, 100);
        uint96 subvault1 = _rootIndex(uint32(1));

        _createSlot(0, false, 100);
        uint96 subvault2 = _rootIndex(uint32(2));

        _createNetworkSlot(subvault1, subnetwork1, 100);
        uint96 networkSlot1 = subvault1.createIndex(uint32(1));

        vm.expectRevert(IUniversalDelegator.AlreadyAssigned.selector);
        _createNetworkSlot(subvault2, subnetwork1, 100);

        _createNetworkSlot(subvault2, subnetwork2, 100);
        uint96 networkSlot2 = subvault2.createIndex(uint32(1));

        assertEq(delegator.getSlotOfNetwork(subnetwork1), networkSlot1);
        assertEq(delegator.getSlotOfNetwork(subnetwork2), networkSlot2);
    }

    function test_operatorAssignment_duplicateAndUnassignChecks() public {
        _createSlot(0, false, 100);
        uint96 subvault = _rootIndex(uint32(1));

        bytes32 subnetwork = bytes32(uint256(1));
        _createNetworkSlot(subvault, subnetwork, 100);
        uint96 networkSlot = subvault.createIndex(uint32(1));

        _createOperatorSlot(networkSlot, alice, 60);
        uint96 operatorSlot1 = networkSlot.createIndex(uint32(1));

        assertEq(delegator.getSlotOfOperator(networkSlot, alice), operatorSlot1);

        vm.expectRevert(IUniversalDelegator.AlreadyAssigned.selector);
        _createOperatorSlot(networkSlot, alice, 60);
    }

    function test_operatorAssignment_revertsWhenSlotAlreadyAssigned() public {
        _createSlot(0, false, 100);
        uint96 subvault = _rootIndex(uint32(1));

        bytes32 subnetwork = bytes32(uint256(1));
        _createNetworkSlot(subvault, subnetwork, 100);
        uint96 networkSlot = subvault.createIndex(uint32(1));

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

    function test_getFilledAt_afterSwap_historicalTraversalNoLoop() public {
        _deposit(alice, 120);

        _createSlot(0, false, MAX_AMOUNT);
        uint96 subvault = _rootIndex(uint32(1));

        _createSlot(subvault, false, 120);
        uint96 networkSlot = subvault.createIndex(uint32(1));

        _createSlot(networkSlot, false, 40);
        _createSlot(networkSlot, false, 40);
        _createSlot(networkSlot, false, 40);

        uint96 op2 = networkSlot.createIndex(uint32(2));
        uint96 op3 = networkSlot.createIndex(uint32(3));
        uint48 beforeSwap = uint48(block.timestamp);

        vm.warp(uint256(beforeSwap) + 1);
        delegator.swapSlots(op2, op3);

        assertEq(delegator.getFilledAt(networkSlot, 0, beforeSwap), 120);
        assertEq(delegator.getFilled(networkSlot, 0), 120);
    }

    function test_swapSlots_revertsNotSameParent() public {
        _deposit(alice, 100);

        _createSlot(0, false, 10);
        uint96 rootSlot = _rootIndex(uint32(1));

        _createSlot(0, false, 10);
        uint96 subvault = _rootIndex(uint32(2));
        _createSlot(subvault, false, 10);
        uint96 networkSlot = subvault.createIndex(uint32(1));

        vm.expectRevert(IUniversalDelegator.NotSameParent.selector);
        delegator.swapSlots(rootSlot, networkSlot);
    }

    function test_swapSlots_revertsNotSameAllocated() public {
        _deposit(alice, 50);

        _createSlot(0, false, 100);
        uint96 subvault = _rootIndex(uint32(1));

        _createSlot(subvault, false, 50);
        _createSlot(subvault, false, 50);
        uint96 slot1 = subvault.createIndex(uint32(1));
        uint96 slot2 = subvault.createIndex(uint32(2));

        vm.expectRevert(IUniversalDelegator.NotSameAllocated.selector);
        delegator.swapSlots(slot1, slot2);
    }

    function test_swapSlots_revertsPartiallyAllocated_whenPartiallyAllocatedAtDurationZero() public {
        _deposit(alice, 70);

        _createSlot(0, false, 100);
        uint96 subvault = _rootIndex(uint32(1));

        _createSlot(subvault, false, 50);
        _createSlot(subvault, false, 50);
        uint96 slot1 = subvault.createIndex(uint32(1));
        uint96 slot2 = subvault.createIndex(uint32(2));

        vm.expectRevert(IUniversalDelegator.PartiallyAllocated.selector);
        delegator.swapSlots(slot1, slot2);
    }

    function test_swapSlots_allowsWhenPendingExistsInMaxDurationWindow() public {
        _deposit(alice, 100);

        _createSlot(0, false, 50);
        _createSlot(0, false, 50);
        uint96 slot1 = _rootIndex(uint32(1));
        uint96 slot2 = _rootIndex(uint32(2));

        // Pending withdrawals are still included for maxDuration = epochDuration - 1,
        // so the slot is treated as fully allocated in that window.
        _withdraw(alice, 30);
        assertEq(delegator.getBalance(0, 0), 100);
        assertEq(delegator.getBalance(0, EPOCH_DURATION - 1), 100);

        delegator.swapSlots(slot1, slot2);
        assertEq(delegator.getAllocated(slot1, 0), 50);
        assertEq(delegator.getAllocated(slot2, 0), 50);
    }

    function test_getPendingAt_doesNotUnderflowForSmallTimestamps() public {
        _deposit(alice, 100);

        _createSlot(0, false, 60);
        uint96 slot1 = _rootIndex(uint32(1));

        vm.warp(1);
        delegator.setSize(slot1, 40);

        assertEq(delegator.getPendingAt(slot1, 0, 2), 20);
        assertEq(delegator.getPendingAt(slot1, 0, 4), 0);
    }

    function test_miscViewsAndMaxNetworkLimitMethods() public {
        address network = makeAddr("misc-network");
        address middleware = makeAddr("misc-middleware");
        _registerNetwork(network, middleware);
        bytes32 subnetwork = network.subnetwork(1);

        assertEq(delegator.VERSION(), 2);
        assertEq(delegator.maxNetworkLimit(bytes32(0)), 0);

        vm.expectRevert(IUniversalDelegator.NotNetwork.selector);
        delegator.setMaxNetworkLimit(1, 123);

        vm.prank(network);
        vm.expectRevert(IUniversalDelegator.LimitNotUint256Max.selector);
        delegator.setMaxNetworkLimit(2, 123);

        vm.prank(network);
        delegator.setMaxNetworkLimit(1, type(uint256).max);
        assertEq(delegator.maxNetworkLimit(subnetwork), type(uint208).max);

        vm.prank(network);
        vm.expectRevert(IUniversalDelegator.AlreadySet.selector);
        delegator.setMaxNetworkLimit(1, type(uint256).max);

        assertEq(delegator.getWithdrawalBuffer(), 0);
    }

    function test_setWithdrawalBufferSize_requiresRole_andUpdatesValue() public {
        _deposit(alice, 100);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, owner, SET_WITHDRAWAL_BUFFER_SIZE_ROLE
            )
        );
        delegator.setWithdrawalBufferSize(40);

        delegator.grantRole(SET_WITHDRAWAL_BUFFER_SIZE_ROLE, owner);
        delegator.setWithdrawalBufferSize(40);
        assertEq(delegator.getWithdrawalBuffer(), 40);

        delegator.setWithdrawalBufferSize(120);
        assertEq(delegator.getWithdrawalBuffer(), 100);
    }

    function test_slotExists_revertsForMissingSlot() public {
        vm.expectRevert(IUniversalDelegator.SlotNotCreated.selector);
        delegator.setSize(_rootIndex(uint32(1)), 1);
    }

    function test_modifier_slotExists_harness() public {
        UniversalDelegatorCoverageHarness harness = new UniversalDelegatorCoverageHarness();

        vm.expectRevert(IUniversalDelegator.SlotNotCreated.selector);
        harness.exposeSlotExists(_rootIndex(uint32(1)));

        harness.setSlotExistsRaw(_rootIndex(uint32(1)), true);
        harness.exposeSlotExists(_rootIndex(uint32(1)));
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

    function test_slotCounters_trackTotalAndExistingChildren() public {
        delegator.grantRole(REMOVE_SLOT_ROLE, owner);

        uint96 slot1 = delegator.createSlot(bytes32(0), 0, false, false, 0);
        uint96 slot2 = delegator.createSlot(bytes32(0), 0, false, false, 0);

        IUniversalDelegator.Slot memory root = delegator.getSlot(0);
        assertEq(root.totalChildren, 2);
        assertEq(root.existChildren, 2);
        assertEq(root.firstChild, slot1.getChildIndex());
        assertEq(root.lastChild, slot2.getChildIndex());

        delegator.removeSlot(slot1);

        root = delegator.getSlot(0);
        assertEq(root.totalChildren, 2);
        assertEq(root.existChildren, 1);
        assertEq(root.firstChild, slot2.getChildIndex());
        assertEq(root.lastChild, slot2.getChildIndex());
    }

    function test_createSlot_returnsCreatedIndex() public {
        uint96 slot1 = delegator.createSlot(bytes32(0), 0, false, false, 0);
        uint96 slot2 = delegator.createSlot(bytes32(0), 0, false, false, 0);

        assertEq(slot1, _rootIndex(1));
        assertEq(slot2, _rootIndex(2));
        assertTrue(delegator.getSlot(slot1).exists);
        assertTrue(delegator.getSlot(slot2).exists);
    }

    function test_syncPrevSums_pathForNonRootParent_afterSlash() public {
        _deposit(alice, 100);

        bytes32 subnetwork = makeAddr("non-root-sync-subnetwork").subnetwork(0);
        _createSlot(0, false, 100);
        uint96 subvault = _rootIndex(uint32(1));
        _createNetworkSlot(subvault, subnetwork, 100);
        uint96 networkSlot = subvault.createIndex(uint32(1));
        _createOperatorSlot(networkSlot, alice, 60);
        _createOperatorSlot(networkSlot, bob, 40);
        uint96 operatorSlot = networkSlot.createIndex(uint32(1));

        vm.prank(address(slasher));
        delegator.onSlash(subnetwork, alice, 1, bytes(""));

        uint128 currentSize = delegator.getSlot(operatorSlot).size;
        delegator.setSize(operatorSlot, currentSize);
        assertEq(delegator.getPending(operatorSlot, 0), 0);
    }

    function test_viewWrappersAndHints() public {
        _deposit(alice, 100);

        address network = makeAddr("wrap-network");
        address middleware = makeAddr("wrap-middleware");
        _registerNetwork(network, middleware);
        bytes32 subnetwork = network.subnetwork(0);
        vm.prank(network);
        delegator.setMaxNetworkLimit(0, type(uint256).max);

        _createSlot(0, false, 100);
        uint96 subvault = _rootIndex(uint32(1));
        _createNetworkSlot(subvault, subnetwork, 100);
        uint96 networkSlot = subvault.createIndex(uint32(1));
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

        assertEq(delegator.getAllocatedAt(subnetwork, alice, 0, uint48(block.timestamp)), 80);
        assertEq(delegator.getAllocated(subnetwork, alice, 0), 80);
        assertEq(delegator.getAllocatedAt(operatorSlot, EPOCH_DURATION + 1, uint48(block.timestamp)), 0);
        assertEq(delegator.getAllocated(operatorSlot, EPOCH_DURATION + 1), 0);

        assertEq(delegator.getBalanceAt(operatorSlot, 0, uint48(block.timestamp)), 80);
        assertEq(delegator.getBalanceAt(0, 0, uint48(block.timestamp)), 100);
        assertEq(delegator.getBalance(operatorSlot, 0), 80);
        assertEq(delegator.getPendingAt(operatorSlot, 0, uint48(block.timestamp)), 0);
        assertEq(delegator.getPending(operatorSlot, 0), 0);
    }

    function test_stakeFor_usesMaxNetworkLimitAsGate_notAsCap() public {
        _deposit(alice, 100);

        address network = makeAddr("stake-gate-network");
        address middleware = makeAddr("stake-gate-middleware");
        _registerNetwork(network, middleware);
        bytes32 subnetwork = network.subnetwork(0);

        _createSlot(0, false, 100);
        uint96 subvault = _rootIndex(uint32(1));
        _createNetworkSlot(subvault, subnetwork, 100);
        uint96 networkSlot = subvault.createIndex(uint32(1));
        _createOperatorSlot(networkSlot, alice, 80);

        assertEq(delegator.stake(subnetwork, alice), 80);
        assertEq(delegator.stakeAt(subnetwork, alice, uint48(block.timestamp), ""), 80);
        assertEq(delegator.stakeFor(subnetwork, alice, 0), 0);
        assertEq(delegator.stakeForAt(subnetwork, alice, 0, uint48(block.timestamp)), 0);

        vm.prank(network);
        delegator.setMaxNetworkLimit(0, type(uint256).max);

        assertEq(delegator.stakeFor(subnetwork, alice, 0), 80);
        assertEq(delegator.stakeForAt(subnetwork, alice, 0, uint48(block.timestamp)), 80);
    }

    function test_stakeFor_simulation_twoEpochTimeline_withReports() public {
        address network = makeAddr("stake-sim-network");
        address middleware = makeAddr("stake-sim-middleware");
        _registerNetwork(network, middleware);
        bytes32 subnetwork = network.subnetwork(0);

        vm.prank(network);
        delegator.setMaxNetworkLimit(0, type(uint256).max);

        _createSlot(0, false, MAX_AMOUNT);
        uint96 subvault = _rootIndex(uint32(1));
        _createNetworkSlot(subvault, subnetwork, MAX_AMOUNT);
        uint96 networkSlot = subvault.createIndex(uint32(1));
        _createOperatorSlot(networkSlot, alice, MAX_AMOUNT);
        uint96 operatorSlot = networkSlot.createIndex(uint32(1));

        _deposit(alice, 200);

        StakeTimelineSnapshot memory snapshot = _snapshotStakeTimeline(subnetwork, alice);
        _reportStakeTimeline("t0/start", snapshot);
        _assertStakeForInvariantForThreeSlots(address(vault), address(delegator), operatorSlot, 0, 0, EPOCH_DURATION);
        assertEq(snapshot.timestamp, 0);
        assertEq(snapshot.activeStake, 200);
        assertEq(snapshot.activeWithdrawals0, 0);
        assertEq(snapshot.stakeFor0, 200);
        assertEq(snapshot.stakeFor1, 200);
        assertEq(snapshot.stakeForMaxDuration, 200);
        assertEq(snapshot.stakeForEpoch, 0);

        vm.warp(1);
        _withdraw(alice, 40);
        delegator.setSize(operatorSlot, 150);
        snapshot = _snapshotStakeTimeline(subnetwork, alice);
        _reportStakeTimeline("t1/withdraw+setSize", snapshot);
        _assertStakeForInvariantForThreeSlots(address(vault), address(delegator), operatorSlot, 0, 0, EPOCH_DURATION);
        assertEq(snapshot.activeStake, 160);
        assertEq(snapshot.activeWithdrawals0, 40);
        assertEq(snapshot.stakeFor0, 200);
        assertEq(snapshot.stakeForMaxDuration, 200);
        assertEq(snapshot.stakeForEpoch, 0);
        assertEq(snapshot.stakeFor0, snapshot.stakeForMaxDuration);

        vm.warp(2);
        _deposit(bob, 30);
        delegator.setSize(operatorSlot, 110);
        snapshot = _snapshotStakeTimeline(subnetwork, alice);
        _reportStakeTimeline("t2/deposit+setSize", snapshot);
        _assertStakeForInvariantForThreeSlots(address(vault), address(delegator), operatorSlot, 0, 0, EPOCH_DURATION);
        assertEq(snapshot.activeStake, 190);
        assertEq(snapshot.activeWithdrawals0, 40);
        assertEq(snapshot.stakeFor0, 200);
        assertEq(snapshot.stakeForMaxDuration, 150);
        assertEq(snapshot.stakeForEpoch, 0);
        assertGt(snapshot.stakeFor0, snapshot.stakeForMaxDuration);

        vm.warp(3);
        _withdraw(bob, 20);
        delegator.setSize(operatorSlot, 140);
        snapshot = _snapshotStakeTimeline(subnetwork, alice);
        _reportStakeTimeline("t3/withdraw+setSize", snapshot);
        _assertStakeForInvariantForThreeSlots(address(vault), address(delegator), operatorSlot, 0, 0, EPOCH_DURATION);
        assertEq(snapshot.activeStake, 170);
        assertEq(snapshot.activeWithdrawals0, 60);
        assertEq(snapshot.activeWithdrawals1, 20);
        assertEq(snapshot.activeWithdrawalsEpoch, 0);
        assertEq(snapshot.stakeFor0, 230);
        assertEq(snapshot.stakeFor1, 180);
        assertEq(snapshot.stakeForMaxDuration, 140);
        assertEq(snapshot.stakeForEpoch, 0);
        assertGt(snapshot.stakeFor0, snapshot.stakeFor1);
        assertGt(snapshot.stakeFor1, snapshot.stakeForMaxDuration);

        vm.warp(4);
        _deposit(alice, 25);
        delegator.setSize(operatorSlot, 130);
        snapshot = _snapshotStakeTimeline(subnetwork, alice);
        _reportStakeTimeline("t4/deposit+setSize", snapshot);
        _assertStakeForInvariantForThreeSlots(address(vault), address(delegator), operatorSlot, 0, 0, EPOCH_DURATION);
        assertEq(snapshot.activeStake, 195);
        assertEq(snapshot.activeWithdrawals0, 20);
        assertEq(snapshot.stakeFor0, 180);
        assertEq(snapshot.stakeForMaxDuration, 140);
        assertEq(snapshot.stakeForEpoch, 0);
        assertGt(snapshot.stakeFor0, snapshot.stakeForMaxDuration);

        vm.warp(5);
        _withdraw(alice, 15);
        delegator.setSize(operatorSlot, 160);
        snapshot = _snapshotStakeTimeline(subnetwork, alice);
        _reportStakeTimeline("t5/withdraw+setSize", snapshot);
        _assertStakeForInvariantForThreeSlots(address(vault), address(delegator), operatorSlot, 0, 0, EPOCH_DURATION);
        assertEq(snapshot.activeStake, 180);
        assertEq(snapshot.activeWithdrawals0, 35);
        assertEq(snapshot.stakeFor0, 170);
        assertEq(snapshot.stakeForMaxDuration, 160);
        assertEq(snapshot.stakeForEpoch, 0);

        vm.warp(7);
        snapshot = _snapshotStakeTimeline(subnetwork, alice);
        _reportStakeTimeline("t7/2-epochs", snapshot);
        _assertStakeForInvariantForThreeSlots(address(vault), address(delegator), operatorSlot, 0, 0, EPOCH_DURATION);
        assertEq(snapshot.activeStake, 180);
        assertEq(snapshot.activeWithdrawals0, 15);
        assertEq(snapshot.stakeFor0, 160);
        assertEq(snapshot.stakeForMaxDuration, 160);
        assertEq(snapshot.stakeForEpoch, 0);

        assertEq(delegator.getSlotOfOperator(networkSlot, alice), operatorSlot);
    }

    function test_stakeFor_simulation_setSizesDepositWithdrawEpochMinusOne_thenSetSizeZero() public {
        address network = makeAddr("stake-sim2-network");
        address middleware = makeAddr("stake-sim2-middleware");
        _registerNetwork(network, middleware);
        bytes32 subnetwork = network.subnetwork(0);

        vm.prank(network);
        delegator.setMaxNetworkLimit(0, type(uint256).max);

        _createSlot(0, false, 0);
        uint96 subvault = _rootIndex(uint32(1));
        _createNetworkSlot(subvault, subnetwork, 0);
        uint96 networkSlot = subvault.createIndex(uint32(1));
        _createOperatorSlot(networkSlot, alice, 0);
        uint96 operatorSlot = networkSlot.createIndex(uint32(1));

        // setSizes(100)
        delegator.setSize(subvault, 100);
        delegator.setSize(networkSlot, 100);
        delegator.setSize(operatorSlot, 100);

        StakeTimelineSnapshot memory snapshot = _snapshotStakeTimeline(subnetwork, alice);
        _reportStakeTimeline("s0/setSizes(100)", snapshot);
        _assertStakeForInvariantForThreeSlots(address(vault), address(delegator), operatorSlot, 0, 0, EPOCH_DURATION);
        assertEq(snapshot.timestamp, 0);
        assertEq(snapshot.activeStake, 0);
        assertEq(snapshot.activeWithdrawals0, 0);
        assertEq(snapshot.stakeFor0, 0);
        assertEq(snapshot.stakeFor1, 0);
        assertEq(snapshot.stakeForMaxDuration, 0);
        assertEq(snapshot.stakeForEpoch, 0);

        // deposit(100)
        vm.warp(1);
        _deposit(alice, 100);
        snapshot = _snapshotStakeTimeline(subnetwork, alice);
        _reportStakeTimeline("s1/deposit(100)", snapshot);
        _assertStakeForInvariantForThreeSlots(address(vault), address(delegator), operatorSlot, 0, 0, EPOCH_DURATION);
        assertEq(snapshot.activeStake, 100);
        assertEq(snapshot.activeWithdrawals0, 0);
        assertEq(snapshot.stakeFor0, 100);
        assertEq(snapshot.stakeFor1, 100);
        assertEq(snapshot.stakeForMaxDuration, 100);
        assertEq(snapshot.stakeForEpoch, 0);

        // withdraw(100)
        vm.warp(2);
        _withdraw(alice, 100);
        snapshot = _snapshotStakeTimeline(subnetwork, alice);
        _reportStakeTimeline("s2/withdraw(100)", snapshot);
        _assertStakeForInvariantForThreeSlots(address(vault), address(delegator), operatorSlot, 0, 0, EPOCH_DURATION);
        assertEq(snapshot.activeStake, 0);
        assertEq(snapshot.activeWithdrawals0, 100);
        assertEq(snapshot.activeWithdrawals1, 100);
        assertEq(snapshot.activeWithdrawalsEpoch, 0);
        assertEq(snapshot.stakeFor0, 100);
        assertEq(snapshot.stakeFor1, 100);
        assertEq(snapshot.stakeForMaxDuration, 100);
        assertEq(snapshot.stakeForEpoch, 0);
        assertEq(snapshot.stakeFor0, snapshot.stakeForMaxDuration);
        assertGt(snapshot.activeWithdrawals0, snapshot.activeWithdrawalsEpoch);

        // wait epoch-1, setSize(0) for operator
        vm.warp(4);
        delegator.setSize(operatorSlot, 0);
        snapshot = _snapshotStakeTimeline(subnetwork, alice);
        _reportStakeTimeline("s3/wait(epoch-1)+setSize(0)", snapshot);
        _assertStakeForInvariantForThreeSlots(address(vault), address(delegator), operatorSlot, 0, 0, EPOCH_DURATION);
        assertEq(snapshot.activeStake, 0);
        assertEq(snapshot.activeWithdrawals0, 100);
        assertEq(snapshot.activeWithdrawals1, 0);
        assertEq(snapshot.activeWithdrawalsEpoch, 0);
        assertEq(snapshot.stakeFor0, 100);
        assertEq(snapshot.stakeFor1, 0);
        assertEq(snapshot.stakeForMaxDuration, 0);
        assertEq(snapshot.stakeForEpoch, 0);
        assertGt(snapshot.stakeFor0, snapshot.stakeForEpoch);
        assertEq(snapshot.stakeFor1, snapshot.stakeForEpoch);

        // wait 1
        vm.warp(5);
        snapshot = _snapshotStakeTimeline(subnetwork, alice);
        _reportStakeTimeline("s4/wait(1)", snapshot);
        _assertStakeForInvariantForThreeSlots(address(vault), address(delegator), operatorSlot, 0, 0, EPOCH_DURATION);
        assertEq(snapshot.activeStake, 0);
        assertEq(snapshot.activeWithdrawals0, 0);
        assertEq(snapshot.activeWithdrawals1, 0);
        assertEq(snapshot.activeWithdrawalsEpoch, 0);
        assertEq(snapshot.stakeFor0, 0);
        assertEq(snapshot.stakeFor1, 0);
        assertEq(snapshot.stakeForMaxDuration, 0);
        assertEq(snapshot.stakeForEpoch, 0);
        assertEq(snapshot.stakeFor0, snapshot.stakeForEpoch);
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

        uint96 subvault = delegator.createSlot(bytes32(0), 0, false, true, 40);
        bytes32 subnetwork = makeAddr("no-plugins-network").subnetwork(0);
        delegator.createSlot(subnetwork, subvault, false, false, 40);

        assertTrue(delegator.getIsNoPlugins(subnetwork));
        assertEq(delegator.getNoPluginsSize(), 40);

        vm.expectRevert(IUniversalDelegator.NotEnoughNoPlugins.selector);
        delegator.setSize(subvault, 200);

        vm.warp(1);
        delegator.setSize(subvault, 10);
        assertEq(delegator.getPending(subvault, 0), 30);
        assertEq(delegator.getNoPluginsSize(), 40);

        vm.warp(EPOCH_DURATION + 1);
        assertEq(delegator.getNoPluginsSize(), 10);
    }

    function test_createSlot_revertsTooManySubvaults() public {
        for (uint256 i; i < MAX_SUBVAULTS; ++i) {
            _createSlot(0, false, 0);
        }

        vm.expectRevert(IUniversalDelegator.TooManyChildren.selector);
        _createSlot(0, false, 0);
    }

    function test_createSlot_revertsTooManyNetworksPerSubvault() public {
        _createSlot(0, false, 0);
        uint96 subvault = _rootIndex(uint32(1));

        for (uint256 i; i < MAX_NETWORKS; ++i) {
            bytes32 subnetwork = bytes32(i + 1);
            delegator.createSlot(subnetwork, subvault, false, false, 0);
        }

        vm.expectRevert(IUniversalDelegator.TooManyChildren.selector);
        delegator.createSlot(bytes32(MAX_NETWORKS + 1), subvault, false, false, 0);
    }

    function test_createSlot_revertsTooManyOperatorsPerNetwork() public {
        _createSlot(0, false, 0);
        uint96 subvault = _rootIndex(uint32(1));
        uint96 networkSlot = delegator.createSlot(bytes32("network"), subvault, false, false, 0);

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
        uint96 subvault = _rootIndex(uint32(1));
        _createSlot(subvault, false, 50);
        _createSlot(subvault, false, 50);

        vm.expectRevert(IUniversalDelegator.IsShared.selector);
        delegator.swapSlots(subvault.createIndex(uint32(1)), subvault.createIndex(uint32(2)));
    }

    function test_removeSlot_revertsWhenAllocated() public {
        delegator.grantRole(REMOVE_SLOT_ROLE, owner);
        _deposit(alice, 100);
        _createSlot(0, false, 100);
        uint96 slot = _rootIndex(uint32(1));

        vm.expectRevert(IUniversalDelegator.SlotAllocated.selector);
        delegator.removeSlot(slot);
    }

    function test_removeSlot_lastRootSubvault_resetsWithdrawalBufferPrevSum() public {
        delegator.grantRole(REMOVE_SLOT_ROLE, owner);

        _deposit(alice, 100);
        _createSlot(0, false, 100);
        uint96 slot = _rootIndex(uint32(1));

        assertEq(delegator.getWithdrawalBuffer(), 0);

        _withdraw(alice, 100);
        vm.warp(block.timestamp + EPOCH_DURATION + 1);
        assertEq(delegator.getAllocated(slot, 0), 0);

        delegator.removeSlot(slot);
        assertFalse(delegator.getSlot(slot).exists);

        _deposit(alice, 100);
        assertEq(delegator.getWithdrawalBuffer(), 100);
    }

    function test_removeSlot_clearsNetworkAndOperatorAssignments() public {
        delegator.grantRole(REMOVE_SLOT_ROLE, owner);
        _createSlot(0, false, 100);
        uint96 subvault = _rootIndex(uint32(1));

        bytes32 subnetwork1 = makeAddr("remove-network-1").subnetwork(0);
        address network2 = makeAddr("remove-network-2");
        address middleware2 = makeAddr("remove-middleware-2");
        _registerNetwork(network2, middleware2);
        bytes32 subnetwork2 = network2.subnetwork(0);
        bytes32 subnetwork3 = makeAddr("remove-network-3").subnetwork(0);
        delegator.createSlot(subnetwork1, subvault, false, false, 0);
        delegator.createSlot(subnetwork2, subvault, false, false, 0);
        delegator.createSlot(subnetwork3, subvault, false, false, 0);
        uint96 networkSlot1 = subvault.createIndex(uint32(1));
        uint96 networkSlot2 = subvault.createIndex(uint32(2));

        vm.prank(network2);
        delegator.setMaxNetworkLimit(0, type(uint256).max);
        delegator.removeSlot(networkSlot2);
        assertEq(delegator.getSlotOfNetwork(subnetwork2), 0);
        assertEq(delegator.maxNetworkLimit(subnetwork2), 0);

        delegator.createSlot(_operatorKey(alice), networkSlot1, false, false, 0);
        uint96 operatorSlot = networkSlot1.createIndex(uint32(1));
        delegator.removeSlot(operatorSlot);
        assertEq(delegator.getSlotOfOperator(networkSlot1, alice), 0);
    }

    function test_removeSlot_noPluginsSubvault_decrementsNoPluginsSize() public {
        delegator.grantRole(REMOVE_SLOT_ROLE, owner);

        _deposit(alice, 100);
        uint96 noPluginsSubvault = delegator.createSlot(bytes32(0), 0, false, true, 100);
        assertEq(delegator.getNoPluginsSize(), 100);
        assertEq(delegator.getAllocated(noPluginsSubvault, 0), 100);

        _withdraw(alice, 100);
        vm.warp(block.timestamp + EPOCH_DURATION + 1);
        assertEq(delegator.getAllocated(noPluginsSubvault, 0), 0);

        delegator.removeSlot(noPluginsSubvault);
        assertFalse(delegator.getSlot(noPluginsSubvault).exists);
        assertEq(delegator.getNoPluginsSize(), 0);
    }

    function test_resetAllocation_lastRootSubvault_keepsWithdrawalBufferConsistent() public {
        address network = makeAddr("reset-last-subvault-network");
        address middleware = makeAddr("reset-last-subvault-middleware");
        _registerNetwork(network, middleware);
        bytes32 subnetwork = network.subnetwork(0);
        vm.prank(network);
        delegator.setMaxNetworkLimit(0, type(uint256).max);

        _deposit(alice, 100);
        uint96 subvault = delegator.createSlot(bytes32(0), 0, false, false, 100);
        uint96 networkSlot = delegator.createSlot(subnetwork, subvault, false, false, 100);
        assertEq(delegator.getSlotOfNetwork(subnetwork), networkSlot);
        assertEq(delegator.getWithdrawalBuffer(), 0);

        _withdraw(alice, 100);
        vm.warp(block.timestamp + EPOCH_DURATION + 1);
        assertEq(delegator.getAllocated(networkSlot, 0), 0);

        vm.prank(middleware);
        delegator.resetAllocation(subnetwork);

        assertEq(delegator.getSlotOfNetwork(subnetwork), 0);
        assertFalse(delegator.getSlot(subvault).exists);

        _deposit(alice, 100);
        assertEq(delegator.getWithdrawalBuffer(), 100);
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

        uint96 noPluginsSubvault = delegator.createSlot(bytes32(0), 0, false, true, 80);
        uint96 slot2 = delegator.createSlot(bytes32(0), 0, false, false, 1);
        uint96 slot3 = delegator.createSlot(bytes32(0), 0, false, false, 1);
        delegator.createSlot(subnetwork, noPluginsSubvault, false, false, 80);

        vm.warp(1);
        delegator.setSize(noPluginsSubvault, 40);
        assertEq(delegator.getNoPluginsSize(), 80);

        vm.prank(network);
        delegator.resetAllocation(subnetwork);

        assertFalse(delegator.getSlot(noPluginsSubvault).exists);
        assertEq(delegator.getSlotOfNetwork(subnetwork), 0);
        assertEq(delegator.getNoPluginsSize(), 0);
        assertEq(delegator.getAllocated(slot3, 0), 1);
        assertEq(delegator.getAllocatedAt(slot3, 0, uint48(block.timestamp)), 1);

        delegator.setSize(slot2, 2);
        assertEq(delegator.getSlot(slot2).size, 2);
    }

    function test_resetAllocation_clearsOnlyRemovedNoPluginsPending() public {
        address network1 = makeAddr("reset-network-no-plugins-1");
        address middleware1 = makeAddr("reset-middleware-no-plugins-1");
        _registerNetwork(network1, middleware1);
        bytes32 subnetwork1 = network1.subnetwork(0);

        address network2 = makeAddr("reset-network-no-plugins-2");
        address middleware2 = makeAddr("reset-middleware-no-plugins-2");
        _registerNetwork(network2, middleware2);
        bytes32 subnetwork2 = network2.subnetwork(0);
        vm.prank(network1);
        delegator.setMaxNetworkLimit(0, type(uint256).max);
        vm.prank(network2);
        delegator.setMaxNetworkLimit(0, type(uint256).max);

        _deposit(alice, 200);

        uint96 noPluginsSubvault1 = delegator.createSlot(bytes32(0), 0, false, true, 100);
        uint96 noPluginsSubvault2 = delegator.createSlot(bytes32(0), 0, false, true, 100);

        delegator.createSlot(subnetwork1, noPluginsSubvault1, false, false, 100);
        delegator.createSlot(subnetwork2, noPluginsSubvault2, false, false, 100);

        vm.warp(1);
        delegator.setSize(noPluginsSubvault1, 50);
        vm.warp(2);
        delegator.setSize(noPluginsSubvault2, 60);

        assertEq(delegator.getPending(noPluginsSubvault1, 0), 50);
        assertEq(delegator.getPending(noPluginsSubvault2, 0), 40);
        assertEq(delegator.getNoPluginsSize(), 200);

        vm.warp(3);
        vm.prank(network1);
        delegator.resetAllocation(subnetwork1);

        assertFalse(delegator.getSlot(noPluginsSubvault1).exists);
        assertEq(delegator.getSlotOfNetwork(subnetwork1), 0);
        assertEq(delegator.maxNetworkLimit(subnetwork1), 0);
        assertEq(delegator.maxNetworkLimit(subnetwork2), type(uint208).max);
        assertEq(delegator.getNoPluginsSize(), 100);
        assertTrue(delegator.getSlot(noPluginsSubvault2).exists);
        assertEq(delegator.getPending(noPluginsSubvault2, 0), 40);
    }

    function test_resetAllocation_singleNetworkClearsAssignmentAndAllowsReassign() public {
        address network = makeAddr("reset-single-network");
        address middleware = makeAddr("reset-single-middleware");
        _registerNetwork(network, middleware);
        bytes32 subnetwork = network.subnetwork(0);
        vm.prank(network);
        delegator.setMaxNetworkLimit(0, type(uint256).max);

        uint96 subvault = delegator.createSlot(bytes32(0), 0, false, false, 0);
        uint96 slot = delegator.createSlot(subnetwork, subvault, false, false, 0);
        assertEq(delegator.getSlotOfNetwork(subnetwork), slot);
        assertEq(delegator.maxNetworkLimit(subnetwork), type(uint208).max);

        vm.prank(middleware);
        delegator.resetAllocation(subnetwork);

        assertEq(delegator.getSlotOfNetwork(subnetwork), 0);
        assertEq(delegator.maxNetworkLimit(subnetwork), 0);

        uint96 newSubvault = delegator.createSlot(bytes32(0), 0, false, false, 0);
        uint96 newSlot = delegator.createSlot(subnetwork, newSubvault, false, false, 0);
        assertEq(delegator.getSlotOfNetwork(subnetwork), newSlot);
    }

    function test_onSlash_noPluginsRootDecreasesNoPluginsSize() public {
        _deposit(alice, 100);

        bytes32 subnetwork = makeAddr("no-plugins-on-slash").subnetwork(0);
        uint96 subvault = delegator.createSlot(bytes32(0), 0, false, true, 80);
        delegator.createSlot(subnetwork, subvault, false, false, 80);
        uint96 networkSlot = subvault.createIndex(uint32(1));
        delegator.createSlot(_operatorKey(alice), networkSlot, false, false, 80);

        assertEq(delegator.getNoPluginsSize(), 80);
        assertEq(delegator.getSlot(subvault).size, 80);

        vm.prank(address(slasher));
        delegator.onSlash(subnetwork, alice, 20, bytes(""));

        assertEq(delegator.getNoPluginsSize(), 60);
        assertEq(delegator.getSlot(subvault).size, 60);
    }

    function test_setHookAndOnSlashPaths() public {
        vm.expectRevert(IUniversalDelegator.NotSlasher.selector);
        delegator.onSlash(bytes32(0), address(0), 0, "");

        delegator.grantRole(HOOK_SET_ROLE, owner);
        UniversalDelegatorHookMock hookMock = new UniversalDelegatorHookMock();
        delegator.setHook(address(hookMock));
        delegator.setHook(address(hookMock));
        assertEq(delegator.hook(), address(hookMock));

        _deposit(alice, 100);

        bytes32 subnetwork = makeAddr("slash-subnetwork").subnetwork(0);
        uint96 subvault = delegator.createSlot(bytes32(0), 0, false, true, 80);
        delegator.createSlot(subnetwork, subvault, false, false, 80);
        uint96 networkSlot = subvault.createIndex(uint32(1));
        delegator.createSlot(_operatorKey(alice), networkSlot, false, false, 20);
        delegator.createSlot(_operatorKey(bob), networkSlot, false, false, 20);
        uint96 operatorSlot1 = networkSlot.createIndex(uint32(1));
        uint96 operatorSlot2 = networkSlot.createIndex(uint32(2));

        vm.warp(1);
        delegator.setSize(subvault, 40);
        delegator.setSize(operatorSlot1, 10);

        vm.prank(address(slasher));
        delegator.onSlash(subnetwork, alice, 50, bytes("payload"));

        assertEq(delegator.getPending(operatorSlot1, 0), 0);
        assertEq(delegator.getPending(subvault, 0), 0);
        assertEq(hookMock.calls(), 1);
        assertEq(hookMock.lastSubnetwork(), subnetwork);
        assertEq(hookMock.lastOperator(), alice);
        assertEq(hookMock.lastAmount(), 50);
        assertEq(hookMock.lastData(), bytes("payload"));
        assertGt(delegator.getAllocated(operatorSlot2, 0), 0);
        assertGt(delegator.getAllocatedAt(operatorSlot2, 0, uint48(block.timestamp)), 0);

        uint256 gasToSend = HOOK_RESERVE + HOOK_GAS_LIMIT * 64 / 63 - 1;
        vm.expectRevert(IUniversalDelegator.InsufficientHookGas.selector);
        vm.prank(address(slasher));
        delegator.onSlash{gas: gasToSend}(subnetwork, alice, 1, bytes(""));
    }

    function test_setSize_sameValue_afterSlashSync_returnsZero() public {
        _deposit(alice, 100);

        bytes32 subnetwork = makeAddr("sync-slot-subnetwork").subnetwork(0);
        _createSlot(0, false, 100);
        uint96 subvault = _rootIndex(uint32(1));
        _createNetworkSlot(subvault, subnetwork, 100);
        uint96 networkSlot = subvault.createIndex(uint32(1));
        _createOperatorSlot(networkSlot, alice, 100);

        vm.prank(address(slasher));
        delegator.onSlash(subnetwork, alice, 1, bytes(""));

        uint128 currentSize = delegator.getSlot(subvault).size;
        delegator.setSize(subvault, currentSize);
        assertEq(delegator.getPending(subvault, 0), 0);
    }

    function test_initializeReverts_NotVault_OldVault_AndAllowsMissingRoleHolders() public {
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
        delegatorFactory.create(UNIVERSAL_DELEGATOR_TYPE, abi.encode(oldVault, abi.encode(params)));

        params.defaultAdminRoleHolder = address(0);
        params.createSlotRoleHolder = address(0);
        address noRoleDelegator =
            delegatorFactory.create(UNIVERSAL_DELEGATOR_TYPE, abi.encode(address(vault), abi.encode(params)));
        assertEq(UniversalDelegator(noRoleDelegator).vault(), address(vault));

        vm.expectRevert();
        UniversalDelegator(noRoleDelegator).createSlot(bytes32(0), 0, false, false, 1);
    }

    function test_migrateReverts_NotVault() public {
        vm.expectRevert(IUniversalDelegator.NotVault.selector);
        delegator.migrate(address(0xBEEF));
    }

    function test_migrate_fromVault_createsNoPluginsSubvault() public {
        MockLegacyDelegatorType oldDelegator = new MockLegacyDelegatorType(0);
        vm.prank(address(vault));
        delegator.migrate(address(oldDelegator));

        IUniversalDelegator.Slot memory root = delegator.getSlot(0);
        assertEq(root.existChildren, 1);
        assertEq(root.firstChild, 1);

        IUniversalDelegator.Slot memory noPluginsSubvault = delegator.getSlot(uint96(0).createIndex(root.firstChild));
        assertTrue(noPluginsSubvault.noPlugins);
        assertTrue(noPluginsSubvault.isShared);
        assertEq(uint256(noPluginsSubvault.size), IUniversalDelegator(address(delegator)).getNoPluginsSize());
    }

    function test_migrate_fromVault_operatorNetworkSpecificLegacy_createsNonSharedNoPluginsSubvault() public {
        MockLegacyDelegatorType oldDelegator = new MockLegacyDelegatorType(OPERATOR_NETWORK_SPECIFIC_DELEGATOR_TYPE);
        vm.prank(address(vault));
        delegator.migrate(address(oldDelegator));

        IUniversalDelegator.Slot memory root = delegator.getSlot(0);
        assertEq(root.existChildren, 1);
        assertEq(root.firstChild, 1);

        IUniversalDelegator.Slot memory noPluginsSubvault = delegator.getSlot(uint96(0).createIndex(root.firstChild));
        assertTrue(noPluginsSubvault.noPlugins);
        assertFalse(noPluginsSubvault.isShared);
        assertEq(uint256(noPluginsSubvault.size), IUniversalDelegator(address(delegator)).getNoPluginsSize());
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
            setSizeRoleHolder: owner,
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
        uint256 available = delegator.getBalance(parentIndex, 0);
        uint256 allocated = delegator.getAllocated(slot1, 0) + delegator.getAllocated(slot2, 0);
        return available > allocated ? available - allocated : 0;
    }

    function _unallocated3(uint96 parentIndex, uint96 slot1, uint96 slot2, uint96 slot3)
        internal
        view
        returns (uint256)
    {
        uint256 available = delegator.getBalance(parentIndex, 0);
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

    function _snapshotStakeTimeline(bytes32 subnetwork, address operator)
        internal
        view
        returns (StakeTimelineSnapshot memory)
    {
        return StakeTimelineSnapshot({
            timestamp: uint48(block.timestamp),
            activeStake: vault.activeStake(),
            activeWithdrawals0: vault.activeWithdrawalsFor(0),
            activeWithdrawals1: vault.activeWithdrawalsFor(1),
            activeWithdrawalsEpoch: vault.activeWithdrawalsFor(EPOCH_DURATION),
            stakeFor0: delegator.stakeFor(subnetwork, operator, 0),
            stakeFor1: delegator.stakeFor(subnetwork, operator, 1),
            stakeForMaxDuration: delegator.stakeFor(subnetwork, operator, EPOCH_DURATION - 1),
            stakeForEpoch: delegator.stakeFor(subnetwork, operator, EPOCH_DURATION)
        });
    }

    function _reportStakeTimeline(string memory label, StakeTimelineSnapshot memory snapshot) internal view {
        console2.log("checkpoint", label);
        console2.log("timestamp", uint256(snapshot.timestamp));
        console2.log("activeStake", snapshot.activeStake);
        console2.log("activeWithdrawalsFor(0)", snapshot.activeWithdrawals0);
        console2.log("activeWithdrawalsFor(1)", snapshot.activeWithdrawals1);
        console2.log("activeWithdrawalsFor(epoch)", snapshot.activeWithdrawalsEpoch);
        console2.log("stakeFor(0)", snapshot.stakeFor0);
        console2.log("stakeFor(1)", snapshot.stakeFor1);
        console2.log("stakeFor(epoch-1)", snapshot.stakeForMaxDuration);
        console2.log("stakeFor(epoch)", snapshot.stakeForEpoch);
    }
}

contract UniversalDelegatorMigrationTest is Test {
    using Subnetwork for address;
    using UniversalDelegatorIndex for uint96;

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
            new VaultV2(
                address(delegatorFactory), address(slasherFactory), address(vaultFactory), address(rewards), address(0)
            )
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

    function test_MigratedUniversalDelegator_MaxNetworkLimitLegacyFallbackAndSeeding() public {
        (IVaultV2 vault_, address oldDelegator,) = _createLegacyVault(0);
        bytes32 subnetwork = network.subnetwork(0);

        vm.prank(network);
        IBaseDelegator(oldDelegator).setMaxNetworkLimit(0, 123);

        bytes memory migrateData = abi.encode(_buildMigrateParams());
        vaultFactory.migrate(address(vault_), vaultFactory.lastVersion(), migrateData);

        IUniversalDelegator newDelegator = IUniversalDelegator(vault_.delegator());
        assertEq(newDelegator.maxNetworkLimit(subnetwork), type(uint208).max);

        IUniversalDelegator.Slot memory root = newDelegator.getSlot(0);
        uint96 noPluginsSubvault = uint96(0).createIndex(root.firstChild);
        newDelegator.createSlot(subnetwork, noPluginsSubvault, false, false, 0);
        assertEq(newDelegator.maxNetworkLimit(subnetwork), type(uint208).max);

        vm.prank(network);
        vm.expectRevert(IUniversalDelegator.AlreadySet.selector);
        newDelegator.setMaxNetworkLimit(0, 1);
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

        (address vaultAddress, address delegatorAddress, address slasherAddress) = vaultConfigurator.create(
            IVaultConfigurator.InitParams({
                version: 1,
                owner: owner,
                vaultParams: abi.encode(baseParams),
                delegatorIndex: delegatorIndex,
                delegatorParams: _legacyDelegatorParams(delegatorIndex),
                withSlasher: false,
                slasherIndex: 0,
                slasherParams: bytes("")
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
            setSizeRoleHolder: owner,
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

        IUniversalDelegator.Slot memory root = IUniversalDelegator(newDelegator).getSlot(0);
        assertEq(root.existChildren, 1);
        IUniversalDelegator.Slot memory noPluginsSubvault =
            IUniversalDelegator(newDelegator).getSlot(uint96(0).createIndex(root.firstChild));
        assertTrue(noPluginsSubvault.noPlugins);
        assertEq(noPluginsSubvault.isShared, legacyType < OPERATOR_NETWORK_SPECIFIC_DELEGATOR_TYPE);
        assertEq(uint256(noPluginsSubvault.size), IUniversalDelegator(newDelegator).getNoPluginsSize());
    }
}
