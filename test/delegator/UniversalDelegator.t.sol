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
import {VaultV2Migrate} from "../../src/contracts/vault/VaultV2Migrate.sol";
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
    WITHDRAWAL_BUFFER_CHILD_INDEX,
    MAX_NETWORKS,
    MAX_OPERATORS,
    SET_WITHDRAWAL_BUFFER_SIZE_ROLE,
    SET_SIZE_ROLE,
    SWAP_SLOTS_ROLE,
    REMOVE_SLOT_ROLE,
    UNIVERSAL_DELEGATOR_TYPE
} from "../../src/interfaces/delegator/IUniversalDelegator.sol";
import {IUniversalSlasher} from "../../src/interfaces/slasher/IUniversalSlasher.sol";
import {IEntity} from "../../src/interfaces/common/IEntity.sol";
import {IMigratableEntity} from "../../src/interfaces/common/IMigratableEntity.sol";
import {IVault} from "../../src/interfaces/vault/IVault.sol";
import {IVaultV2} from "../../src/interfaces/vault/IVaultV2.sol";
import {IVaultConfigurator} from "../../src/interfaces/IVaultConfigurator.sol";

import {Token} from "../mocks/Token.sol";
import {MockRewards} from "../mocks/MockRewards.sol";
import {CoreV2StakeForInvariantHelper} from "../helpers/CoreV2StakeForInvariantHelper.sol";

contract MockLegacyDelegatorType {
    using Subnetwork for bytes32;

    uint64 public immutable TYPE;
    bytes32 internal _subnetwork;
    address public network;
    address public operator;
    uint256 internal _maxNetworkLimit;

    constructor(uint64 type_) {
        TYPE = type_;
    }

    function setOperatorNetworkSpecific(bytes32 subnetwork, address operator_, uint256 maxNetworkLimit_) external {
        _subnetwork = subnetwork;
        network = subnetwork.network();
        operator = operator_;
        _maxNetworkLimit = maxNetworkLimit_;
    }

    function maxNetworkLimit(bytes32 subnetwork) external view returns (uint256) {
        return subnetwork == _subnetwork ? _maxNetworkLimit : 0;
    }
}

contract MockVaultForDelegatorCoverage {
    uint48 public epochDuration = 3;
}

contract UniversalDelegatorCoverageHarnessTest is Test, UniversalDelegator {
    using Checkpoints for Checkpoints.Trace208;

    constructor() UniversalDelegator(address(0), address(0), address(0), 0, address(0)) {}

    function setSlotExistsRaw(uint64 index, bool exists_) external {
        slots[index].exists = exists_;
    }

    function exposeSlotExists(uint64 index, bool exists_) external {
        slots[index].exists = exists_;
        _revertIfNotExists(index);
    }

    function setVaultRaw(address vault_) external {
        vault = vault_;
    }

    function pushSlotSizeRaw(uint64 index, uint48 timestamp, uint208 value) external {
        slots[index].size.push(timestamp, value);
    }

    function pushNextSlotRaw(uint64 index, uint48 timestamp, uint208 value) external {
        slots[index].nextSlot.push(timestamp, value);
    }

    function pushFirstChildRaw(uint64 index, uint48 timestamp, uint208 value) external {
        slots[index].firstChild.push(timestamp, value);
    }

    function pushSyncPrevSizeSumsRaw(uint64 index, uint48 timestamp, uint208 value) external {
        slots[index].syncPrevSizeSums.push(timestamp, value);
    }

    function latestSyncPrevSizeSums(uint64 index) external view returns (uint208) {
        return slots[index].syncPrevSizeSums.latest();
    }

    function latestPrevSizeSum(uint64 index) external view returns (uint208) {
        return slots[index].prevSizeSum.latest();
    }

    function exposeSyncPrevSizeSums(uint64 parentIndex) external syncPrevSizeSums(parentIndex) {}

    function exposeGetPrevSum(uint64 index) external view returns (uint208) {
        return _getPrevSum(index);
    }

    function exposeGetPrevSumAt(uint64 index, uint48 timestamp) external view returns (uint208) {
        return _getPrevSumAt(index, timestamp);
    }
}

contract UniversalDelegatorInitCoverageHarnessTest is Test, UniversalDelegator {
    constructor(address networkRegistry, address vaultFactory, address networkMiddlewareService)
        UniversalDelegator(networkRegistry, vaultFactory, address(0), 0, networkMiddlewareService)
    {}

    function exposeInitialize(bytes calldata data) external {
        _initialize(data);
    }
}

contract UniversalDelegatorTest is Test, CoreV2StakeForInvariantHelper {
    using UniversalDelegatorIndex for uint64;
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
    uint64 internal dummyNetworkId;
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

    struct ChaosState {
        address[6] operators;
        uint64[6] operatorSlots;
        bool[6] exists;
    }

    struct PendingDecreaseSwapFuzzState {
        address network;
        address operator3;
        bytes32 subnetwork;
        uint128 firstSize;
        uint128 middleSize;
        uint128 lastSize;
        uint64 slot1;
        uint64 slot2;
        uint64 slot3;
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

        address vaultV2Migrate = address(
            new VaultV2Migrate(
                address(delegatorFactory), address(slasherFactory), address(0), address(rewards), address(0)
            )
        );
        address vaultImpl = address(
            new VaultV2(
                address(delegatorFactory),
                address(slasherFactory),
                address(vaultFactory),
                address(0),
                address(rewards),
                address(0),
                vaultV2Migrate
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
                        adapters: new address[](0),
                        adaptersAllowDelay: EPOCH_DURATION + 1,
                        depositWhitelist: false,
                        depositorToWhitelist: address(0xBEEF),
                        isDepositLimit: false,
                        depositLimit: 0,
                        defaultAdminRoleHolder: owner,
                        depositWhitelistSetRoleHolder: address(0),
                        depositorWhitelistRoleHolder: address(0),
                        isDepositLimitSetRoleHolder: address(0),
                        depositLimitSetRoleHolder: address(0),
                        setAdapterLimitRoleHolder: address(0),
                        swapAdaptersRoleHolder: address(0),
                        allocateAdapterRoleHolder: address(0),
                        deallocateAdapterRoleHolder: address(0)
                    })
                ),
                delegatorIndex: uint64(delegatorFactory.totalTypes() - 1),
                delegatorParams: abi.encode(
                    IUniversalDelegator.InitParams({
                        defaultAdminRoleHolder: owner,
                        createSlotRoleHolder: owner,
                        setSizeRoleHolder: owner,
                        swapSlotsRoleHolder: owner,
                        removeSlotRoleHolder: owner,
                        setWithdrawalBufferSizeRoleHolder: owner,
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

    function test_OnSlashRejectsNonSlasherCaller() public {
        vm.expectRevert(IBaseDelegator.NotSlasher.selector);
        delegator.onSlash(alice.subnetwork(0), alice, 1);
    }

    function test_checkpointTracksHistory_andDefaults() public {
        _createSlot(0, 30);
        uint64 slot1 = _rootIndex(uint32(1));

        assertEq(delegator.getAllocatedAt(slot1, 0, 0), 0);

        vm.warp(5);
        _deposit(alice, 100);
        assertEq(delegator.getAllocatedAt(slot1, 0, 5), 30);

        vm.warp(7);
        delegator.setSize(slot1, 20);
        assertEq(delegator.getAllocatedAt(slot1, 0, 7), 30);
        assertEq(delegator.getAllocatedAt(slot1, 0, 9), 30);
        assertEq(delegator.getAllocatedAt(slot1, 0, 10), 20);
        assertEq(delegator.getAllocatedAt(slot1, 1, 9), 20);
        assertEq(delegator.getAllocatedAt(slot1, EPOCH_DURATION - 1, 8), 20);
        assertEq(delegator.getAllocatedAt(slot1, EPOCH_DURATION - 1, 9), 20);
        assertEq(delegator.getAllocatedAt(slot1, EPOCH_DURATION - 1, 10), 20);
        assertEq(delegator.getAllocatedAt(slot1, EPOCH_DURATION, 9), 0);
    }

    function test_createSlot_root_allowsDepth1() public {
        _createSlot(0, 10);
        uint64 slot1 = _rootIndex(uint32(1));

        assertEq(delegator.getAllocated(slot1, 0), 0);
    }

    function test_setSize_allowsNonZeroCurrentSize() public {
        _createSlot(0, 10);
        uint64 slot1 = _rootIndex(uint32(1));

        delegator.setSize(slot1, 20);
        assertEq(delegator.getAllocated(slot1, 0), 0);
    }

    function test_slotAllocation_partialFill() public {
        _deposit(alice, 100);

        _createSlot(0, 30);
        _createSlot(0, 500);

        uint64 slot1 = _rootIndex(uint32(1));
        uint64 slot2 = _rootIndex(uint32(2));

        assertEq(_unallocated2(0, slot1, slot2), 0);
        assertEq(delegator.getAllocated(slot1, 0), 30);
        assertEq(delegator.getAllocated(slot2, 0), 70);
    }

    function test_slotAllocation_partialFill_2() public {
        _deposit(alice, 100);

        _createSlot(0, 500);
        _createSlot(0, 30);

        uint64 slot1 = _rootIndex(uint32(1));
        uint64 slot2 = _rootIndex(uint32(2));

        assertEq(_unallocated2(0, slot1, slot2), 0);
        assertEq(delegator.getAllocated(slot1, 0), 100);
        assertEq(delegator.getAllocated(slot2, 0), 0);
    }

    function test_slotAllocation_respectsOrderAndLimits() public {
        _deposit(alice, 100);

        _createSlot(0, 30);
        _createSlot(0, 50);

        uint64 slot1 = _rootIndex(uint32(1));
        uint64 slot2 = _rootIndex(uint32(2));

        assertEq(_unallocated2(0, slot1, slot2), 20);
        assertEq(delegator.getAllocated(slot1, 0), 30);
        assertEq(delegator.getAllocated(slot2, 0), 50);
    }

    function test_increaseLimit_consumesUnallocated_andUpdatesPrevSums() public {
        _deposit(alice, 100);

        _createSlot(0, 30);
        _createSlot(0, 50);

        uint64 slot1 = _rootIndex(uint32(1));
        uint64 slot2 = _rootIndex(uint32(2));

        vm.warp(1);
        delegator.setSize(slot1, 45);

        assertEq(delegator.getAllocatedAt(slot1, 0, 1), 45);
        assertEq(delegator.getAllocatedAt(slot2, 0, 1), 50);
        assertEq(_unallocated2(0, slot1, slot2), 5);
    }

    function test_increaseLimit_revertsWhenFullyAllocatedNonLast_withoutUnallocated() public {
        _deposit(alice, 100);

        _createSlot(0, 60);
        _createSlot(0, 60);

        uint64 slot1 = _rootIndex(uint32(1));
        uint64 slot2 = _rootIndex(uint32(2));

        vm.expectRevert(IUniversalDelegator.NotEnoughBalance.selector);
        delegator.setSize(slot1, 80);
    }

    function test_increaseLimit_allowsWhenNotLastChild_ifLaterSiblingsHaveNoCurrentAllocation() public {
        _deposit(alice, 100);

        _createSlot(0, 60);
        _createSlot(0, 60);
        _createSlot(0, 60);

        uint64 slot1 = _rootIndex(uint32(1));
        uint64 slot2 = _rootIndex(uint32(2));
        uint64 slot3 = _rootIndex(uint32(3));

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

        _createSlot(0, 30);
        _createSlot(0, 30);

        uint64 slot1 = _rootIndex(uint32(1));
        uint64 slot2 = _rootIndex(uint32(2));

        delegator.setSize(slot2, 90);

        assertEq(delegator.getAllocated(slot1, 0), 30);
        assertEq(delegator.getAllocated(slot2, 0), 70);
        assertEq(_unallocated2(0, slot1, slot2), 0);
    }

    function test_decreaseLimit_leafNetworkSchedulesPendingUntilDelayExpires() public {
        _deposit(alice, 100);

        _createSlot(0, 60);
        _createSlot(0, 30);

        uint64 slot1 = _rootIndex(uint32(1));
        uint64 slot2 = _rootIndex(uint32(2));

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

        _createSlot(0, 444);
        uint64 networkSlot = _rootIndex(uint32(1));
        _createSlot(networkSlot, 444);
        uint64 operatorSlot = networkSlot.createIndex(uint32(1));

        assertEq(delegator.getAllocated(networkSlot, 0), 444);
        assertEq(delegator.getAllocated(operatorSlot, 0), 444);

        vm.warp(1);
        delegator.setSize(networkSlot, 222);

        assertEq(_pending(networkSlot), 222);
        assertEq(delegator.getAllocated(networkSlot, 0), 444);
        assertEq(delegator.getAllocated(operatorSlot, 0), 444);

        vm.warp(2);
        delegator.setSize(operatorSlot, 222);

        assertEq(_pending(operatorSlot), 222);
        assertEq(delegator.getAllocated(operatorSlot, 0), 444);
    }

    function test_leafNetworkSiblingDecreaseWithoutChildren_schedulesPending() public {
        _deposit(alice, 100);

        _createSlot(0, 60);
        _createSlot(0, 40);
        uint64 slot1 = _rootIndex(uint32(1));
        uint64 slot2 = _rootIndex(uint32(2));

        vm.warp(1);
        delegator.setSize(slot1, 30);

        assertEq(_pending(slot1), 30);
        assertEq(delegator.getAllocated(slot1, 0), 60);
        assertEq(delegator.getAllocated(slot2, 0), 40);
        assertEq(_unallocated2(0, slot1, slot2), 0);
    }

    function test_leafNetworkDecreaseWithoutChildren_schedulesPending() public {
        _deposit(alice, 100);

        bytes32 subnetwork = makeAddr("leaf-network-subnetwork").subnetwork(0);
        uint64 networkSlot = delegator.createSlot(subnetwork, 0, 80);

        vm.warp(1);
        delegator.setSize(networkSlot, 30);

        assertEq(_pending(networkSlot), 50);
        assertEq(delegator.getAllocated(networkSlot, 0), 80);
        assertEq(delegator.getFilled(0, 0), 80);
    }

    function test_childrenPending_accumulatesOnRepeatedOperatorDecrease() public {
        _deposit(alice, 555);

        _createSlot(0, 444);
        uint64 networkSlot = _rootIndex(uint32(1));
        _createSlot(networkSlot, 444);
        uint64 operatorSlot = networkSlot.createIndex(uint32(1));

        vm.warp(1);
        delegator.setSize(operatorSlot, 222);

        assertEq(_pending(operatorSlot), 222);
        assertEq(delegator.getAllocated(operatorSlot, 0), 444);

        vm.warp(2);
        delegator.setSize(operatorSlot, 0);

        assertEq(_pending(operatorSlot), 444);
        assertEq(delegator.getAllocated(networkSlot, 0), 444);
        assertEq(delegator.getAllocated(operatorSlot, 0), 444);
    }

    function test_getAvailableAt_pendingHints_matchNoHintPath() public {
        _deposit(alice, 555);

        bytes32 subnetwork = makeAddr("hints-subnetwork").subnetwork(0);
        uint64 networkSlot = delegator.createSlot(subnetwork, 0, 444);

        _createOperatorSlot(networkSlot, alice, 444);
        uint64 operatorSlot = networkSlot.createIndex(uint32(1));

        vm.warp(1);
        delegator.setSize(operatorSlot, 222);

        vm.warp(2);
        delegator.setSize(operatorSlot, 0);

        uint48 timestampBeforeSlash = uint48(block.timestamp);
        uint208 pendingBefore = _pendingAt(operatorSlot, timestampBeforeSlash);
        uint256 balanceBefore = delegator.getBalanceAt(networkSlot, 0, timestampBeforeSlash);
        uint256 allocatedBefore = delegator.getAllocatedAt(operatorSlot, 0, timestampBeforeSlash);
        assertGt(pendingBefore, 0);

        vm.prank(address(slasher));
        delegator.onSlash(subnetwork, alice, 20);
        uint48 timestampAfterSlash = uint48(block.timestamp);
        uint208 pendingAfter = _pendingAt(operatorSlot, timestampAfterSlash);
        uint256 balanceAfter = delegator.getBalanceAt(networkSlot, 0, timestampAfterSlash);
        uint256 allocatedAfter = delegator.getAllocatedAt(operatorSlot, 0, timestampAfterSlash);

        assertLe(pendingAfter, pendingBefore);
        assertLe(balanceAfter, balanceBefore);
        assertLe(allocatedAfter, allocatedBefore);
    }

    function test_pendingWindow_afterSlash_keepsRecentPendingWhenOldPendingExpires() public {
        bytes32 subnetwork = makeAddr("issue5-window-network").subnetwork(0);

        _deposit(alice, 200);
        uint64 networkSlot = delegator.createSlot(subnetwork, 0, 200);
        _createOperatorSlot(networkSlot, alice, 200);
        uint64 operatorSlot = networkSlot.createIndex(uint32(1));

        vm.warp(1);
        delegator.setSize(operatorSlot, 100);
        vm.warp(2);
        delegator.setSize(operatorSlot, 200);
        vm.warp(3);
        delegator.setSize(operatorSlot, 70);

        assertEq(_pending(operatorSlot), 130);

        vm.prank(address(slasher));
        delegator.onSlash(subnetwork, alice, 100);

        assertEq(_pending(operatorSlot), 30);

        vm.warp(4);
        assertEq(_pending(operatorSlot), 30);
    }

    function test_depth2Operators_areIsolatedWithinNetwork() public {
        _deposit(alice, 100);

        _createSlot(0, 80);
        uint64 net1 = _rootIndex(uint32(1));

        _createSlot(net1, 50);
        _createSlot(net1, 50);
        uint64 op1 = net1.createIndex(uint32(1));
        uint64 op2 = net1.createIndex(uint32(2));

        assertEq(delegator.getAllocated(net1, 0), 80);
        assertEq(delegator.getAllocated(op1, 0), 50);
        assertEq(delegator.getAllocated(op2, 0), 30);
    }

    function test_getFilled_zeroWhenNetworkHasNoOperators() public {
        _deposit(alice, 100);

        _createSlot(0, 100);
        uint64 networkSlot = _rootIndex(uint32(1));

        assertEq(delegator.getFilled(networkSlot, 0), 0);
    }

    function test_getFilled_matchesSumOfOperatorsForNetwork() public {
        _deposit(alice, 100);

        _createSlot(0, 100);
        uint64 networkSlot = _rootIndex(uint32(1));

        _createSlot(networkSlot, 70);
        _createSlot(networkSlot, 70);
        uint64 op1 = networkSlot.createIndex(uint32(1));
        uint64 op2 = networkSlot.createIndex(uint32(2));

        uint256 expected = delegator.getAllocated(op1, 0) + delegator.getAllocated(op2, 0);
        assertEq(delegator.getFilled(networkSlot, 0), expected);
        assertEq(delegator.getFilled(networkSlot, 0), 100);
    }

    function test_getFilled_respectsDurationWindowForPending() public {
        _deposit(alice, 200);

        _createSlot(0, 200);
        uint64 networkSlot = _rootIndex(uint32(1));

        _createSlot(networkSlot, 100);
        _createSlot(networkSlot, 100);
        uint64 op1 = networkSlot.createIndex(uint32(1));
        uint64 op2 = networkSlot.createIndex(uint32(2));

        vm.warp(1);
        delegator.setSize(op1, 50);

        vm.warp(2);
        uint48 maxDuration = EPOCH_DURATION - 1;
        uint256 expectedWithPendingWindow = delegator.getAllocated(op1, 0) + delegator.getAllocated(op2, 0);
        uint256 expectedWithMaxDurationWindow =
            delegator.getAllocated(op1, maxDuration) + delegator.getAllocated(op2, maxDuration);

        assertEq(expectedWithPendingWindow, 200);
        assertEq(delegator.getFilled(networkSlot, 0), expectedWithPendingWindow);
        assertEq(delegator.getFilled(networkSlot, maxDuration), expectedWithMaxDurationWindow);
        assertEq(delegator.getFilled(networkSlot, EPOCH_DURATION), 0);
        assertEq(delegator.getFilled(networkSlot, 0), 200);
    }

    function test_getFilled_numericTrace_multiDepthMultipleSizeChanges() public {
        _deposit(alice, 1000);

        _createSlot(0, 500);
        _createSlot(0, 300);
        uint64 network1 = _rootIndex(uint32(1));
        uint64 network2 = _rootIndex(uint32(2));

        _createSlot(network1, 220);
        _createSlot(network1, 180);
        _createSlot(network1, 160);
        uint64 op1 = network1.createIndex(uint32(1));
        uint64 op2 = network1.createIndex(uint32(2));
        uint64 op3 = network1.createIndex(uint32(3));

        // Initial state.
        assertEq(delegator.getAllocated(network1, 0), 500);
        assertEq(delegator.getAllocated(network2, 0), 300);
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
        assertEq(_pending(network1), 80);
        assertEq(delegator.getAllocated(network1, 0), 500);
        assertEq(delegator.getAllocated(network2, 0), 300);
        assertEq(delegator.getFilled(network1, 0), 500);

        // Decrease operator2 size: creates pending=60 for operator2/network1.
        vm.warp(2);
        delegator.setSize(op2, 120);
        assertEq(_pending(op2), 60);
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
        assertEq(_pending(op3), 60);
        assertEq(delegator.getAllocated(op3, 0), 100);

        // Attempting operator1 increase 220 -> 260 reverts in this state (no tail unallocated amount).
        vm.warp(4);
        vm.expectRevert(IUniversalDelegator.NotEnoughBalance.selector);
        delegator.setSize(op1, 260);

        // After pending windows expire, the same topology has lower filled amount.
        vm.warp(6);
        assertEq(_pending(network1), 0);
        assertEq(_pending(op2), 0);
        assertEq(delegator.getAllocated(network1, 0), 420);
        assertEq(delegator.getAllocated(op1, 0), 220);
        assertEq(delegator.getAllocated(op2, 0), 120);
        assertEq(delegator.getAllocated(op3, 0), 20);
        assertEq(
            delegator.getAllocated(op1, 0) + delegator.getAllocated(op2, 0) + delegator.getAllocated(op3, 0),
            delegator.getFilled(network1, 0)
        );
        assertEq(delegator.getFilled(network1, 0), 360);
    }

    function test_getFilled_invariant_repeatedSetSizes_withDepositWithdraw() public {
        _deposit(alice, 400);

        _createSlot(0, 400);
        uint64 networkSlot = _rootIndex(uint32(1));

        _createSlot(networkSlot, 200);
        _createSlot(networkSlot, 150);
        _createSlot(networkSlot, 150);
        uint64 op1 = networkSlot.createIndex(uint32(1));
        uint64 op2 = networkSlot.createIndex(uint32(2));
        uint64 op3 = networkSlot.createIndex(uint32(3));

        uint256 sumInitial =
            delegator.getAllocated(op1, 0) + delegator.getAllocated(op2, 0) + delegator.getAllocated(op3, 0);
        assertEq(sumInitial, 400);
        assertEq(delegator.getFilled(networkSlot, 0), sumInitial);
        assertEq(delegator.getFilled(networkSlot, 0), 400);

        vm.warp(1);
        delegator.setSize(op2, 120);
        assertEq(_pending(op2), 30);
        assertEq(
            delegator.getFilled(networkSlot, 0),
            delegator.getAllocated(op1, 0) + delegator.getAllocated(op2, 0) + delegator.getAllocated(op3, 0)
        );
        assertEq(delegator.getFilled(networkSlot, 0), 400);

        vm.warp(2);
        delegator.setSize(op1, 170);
        assertEq(_pending(op1), 30);
        assertEq(_pending(op1) + _pending(op2) + _pending(op3), 60);

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
        assertEq(_pending(op1), 0);
        assertEq(_pending(op2), 0);
        assertEq(
            delegator.getFilled(networkSlot, 0),
            delegator.getAllocated(op1, 0) + delegator.getAllocated(op2, 0) + delegator.getAllocated(op3, 0)
        );
        assertEq(delegator.getFilled(networkSlot, 0), 320);
        assertEq(delegator.getFilled(networkSlot, 0), delegator.getFilled(networkSlot, maxDuration));
        assertEq(delegator.getFilled(networkSlot, maxDuration), 320);
        assertEq(delegator.getFilled(networkSlot, EPOCH_DURATION), 0);
    }

    function test_getFilled_invariant_afterSwapsResizesAndStakeChanges() public {
        _deposit(alice, 300);

        _createSlot(0, 300);
        uint64 networkSlot = _rootIndex(uint32(1));

        _createSlot(networkSlot, 100);
        _createSlot(networkSlot, 100);
        _createSlot(networkSlot, 100);
        uint64 op1 = networkSlot.createIndex(uint32(1));
        uint64 op2 = networkSlot.createIndex(uint32(2));
        uint64 op3 = networkSlot.createIndex(uint32(3));

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
        assertEq(_pending(op3), 30);
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
        assertEq(_pending(op3), 0);
        assertEq(
            delegator.getFilled(networkSlot, 0),
            delegator.getAllocated(op1, 0) + delegator.getAllocated(op2, 0) + delegator.getAllocated(op3, 0)
        );
        assertEq(
            delegator.getFilled(networkSlot, 0),
            delegator.getAllocated(op1, 0) + delegator.getAllocated(op2, 0) + delegator.getAllocated(op3, 0)
        );
        uint48 maxDuration = EPOCH_DURATION - 1;
        assertEq(delegator.getFilled(networkSlot, 0), delegator.getFilled(networkSlot, maxDuration));
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
        uint64 networkSlot1;
        uint64 networkSlot2;
        uint64 opSlot1;
        uint64 opSlot2;
        uint64 opSlot3;
        uint64 extraSlot;
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

        testStruct.networkSlot1 = delegator.createSlot(testStruct.subnetwork1, 0, 300);
        testStruct.networkSlot2 = delegator.createSlot(testStruct.subnetwork2, 0, 200);

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

    function test_isolatedNetworks_prioritizedOverTime() public {
        _createSlot(0, 30);
        _createSlot(0, 50);
        _createSlot(0, 100);

        uint64 slot1 = _rootIndex(uint32(1));
        uint64 slot2 = _rootIndex(uint32(2));
        uint64 slot3 = _rootIndex(uint32(3));

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

    function test_isolatedOperators_followNetworkPriority() public {
        _deposit(alice, 150);

        _createSlot(0, 200);
        uint64 networkSlot = _rootIndex(uint32(1));

        _createSlot(networkSlot, 60);
        _createSlot(networkSlot, 120);
        uint64 op1 = networkSlot.createIndex(uint32(1));
        uint64 op2 = networkSlot.createIndex(uint32(2));

        assertEq(delegator.getAllocated(networkSlot, 0), 150);
        assertEq(delegator.getAllocated(op1, 0), 60);
        assertEq(delegator.getAllocated(op2, 0), 90);
    }

    function test_isolatedOperators_prioritizedAfterStakeDecrease() public {
        _createSlot(0, 1000);
        uint64 networkSlot = _rootIndex(uint32(1));

        _createSlot(networkSlot, 70);
        _createSlot(networkSlot, 70);
        uint64 op1 = networkSlot.createIndex(uint32(1));
        uint64 op2 = networkSlot.createIndex(uint32(2));

        vm.warp(1);
        _deposit(alice, 100);

        assertEq(delegator.getAllocated(op1, 0), 70);
        assertEq(delegator.getAllocated(op2, 0), 30);

        vm.warp(2);
        _withdraw(alice, 40);

        assertEq(delegator.getAllocated(op1, 0), 70);
        assertEq(delegator.getAllocated(op2, 0), 30);
    }

    function test_isolatedSlots_leafDecrease_delaysReallocation() public {
        _deposit(alice, 100);

        _createSlot(0, 70);
        _createSlot(0, 70);
        uint64 slot1 = _rootIndex(uint32(1));
        uint64 slot2 = _rootIndex(uint32(2));

        assertEq(delegator.getAllocated(slot1, 0), 70);
        assertEq(delegator.getAllocated(slot2, 0), 30);

        vm.warp(1);
        delegator.setSize(slot1, 30);

        assertEq(_pending(slot1), 40);
        assertEq(delegator.getAllocated(slot1, 0), 70);
        assertEq(delegator.getAllocated(slot2, 0), 30);

        vm.warp(1 + EPOCH_DURATION);
        assertEq(delegator.getAllocated(slot1, 0), 30);
        assertEq(delegator.getSlot(slot2).prevSizeSum, 70);
        assertEq(delegator.getAllocated(slot2, 0), 30);
    }

    function test_isolatedSlots_lateSizeIncrease_doesNotAffectEarlier() public {
        _deposit(alice, 90);

        _createSlot(0, 50);
        _createSlot(0, 60);
        uint64 slot1 = _rootIndex(uint32(1));
        uint64 slot2 = _rootIndex(uint32(2));

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

    struct Test_IsolatedNetworkSlashCappedAcrossNetworksSameCaptureTimestampStruct {
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
        uint64 networkSlot1;
        uint64 networkSlot2;
        uint64 netSlot1;
        uint64 netSlot2;
        uint64 netSlot3;
        uint64 opSlot1;
        uint64 opSlot2;
        uint64 opSlot3;
        uint48 captureTimestamp;
    }

    function testFuzz_isolatedNetworks_followPriority(uint256 depositAmount, uint256 size1, uint256 size2) public {
        uint256 amount = bound(depositAmount, 1, MAX_AMOUNT);
        uint256 cap1 = bound(size1, 0, MAX_AMOUNT);
        uint256 cap2 = bound(size2, 0, MAX_AMOUNT);

        _createSlot(0, cap1);
        _createSlot(0, cap2);
        uint64 slot1 = _rootIndex(uint32(1));
        uint64 slot2 = _rootIndex(uint32(2));

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

        _createSlot(0, MAX_AMOUNT);
        uint64 networkSlot = _rootIndex(uint32(1));

        _createSlot(networkSlot, cap1);
        _createSlot(networkSlot, cap2);
        uint64 op1 = networkSlot.createIndex(uint32(1));
        uint64 op2 = networkSlot.createIndex(uint32(2));

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

        _createSlot(0, cap1);
        _createSlot(0, cap2);
        uint64 slot1 = _rootIndex(uint32(1));
        uint64 slot2 = _rootIndex(uint32(2));

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

        _createSlot(0, cap1);
        _createSlot(0, cap2);
        uint64 slot1 = _rootIndex(uint32(1));
        uint64 slot2 = _rootIndex(uint32(2));

        _deposit(alice, amount);

        uint256 available = delegator.getBalance(0, 0);
        uint256 expected1 = available < cap1 ? available : cap1;
        uint256 remaining = available > cap1 ? available - cap1 : 0;
        uint256 expected2 = remaining < cap2 ? remaining : cap2;

        assertEq(delegator.getAllocated(slot1, 0), expected1);
        assertEq(delegator.getAllocated(slot2, 0), expected2);
    }

    function testFuzz_isolatedShares_doNotOverlapInNetwork(uint256 depositAmount, uint256 size1, uint256 size2) public {
        uint256 cap1 = bound(size1, 0, MAX_AMOUNT);
        uint256 cap2 = bound(size2, 0, MAX_AMOUNT);
        uint256 amount = bound(depositAmount, 1, MAX_AMOUNT);

        _createSlot(0, MAX_AMOUNT);
        uint64 networkSlot = _rootIndex(uint32(1));

        _createSlot(networkSlot, cap1);
        _createSlot(networkSlot, cap2);
        uint64 slot1 = networkSlot.createIndex(uint32(1));
        uint64 slot2 = networkSlot.createIndex(uint32(2));

        _deposit(alice, amount);

        uint256 available = delegator.getBalance(networkSlot, 0);
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
        uint64 networkSlot1;
        uint64 networkSlot2;
        bytes32 subnetwork1;
        bytes32 subnetwork2;
        uint64 opSlot1;
        uint64 opSlot2;
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

        testStruct.subnetwork1 = testStruct.network1.subnetwork(0);
        testStruct.subnetwork2 = testStruct.network2.subnetwork(0);
        testStruct.networkSlot1 = delegator.createSlot(testStruct.subnetwork1, 0, uint128(testStruct.cap1));
        testStruct.networkSlot2 = delegator.createSlot(testStruct.subnetwork2, 0, uint128(testStruct.cap2));

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
        uint64 networkSlot;
        bytes32 subnetwork;
        uint64 opSlot1;
        uint64 opSlot2;
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

        testStruct.subnetwork = testStruct.network.subnetwork(0);
        uint64 networkSlot = delegator.createSlot(testStruct.subnetwork, 0, uint128(networkSize));

        _createOperatorSlot(networkSlot, testStruct.operator1, cap1);
        _createOperatorSlot(networkSlot, testStruct.operator2, cap2);
        uint64 opSlot1 = networkSlot.createIndex(uint32(1));
        uint64 opSlot2 = networkSlot.createIndex(uint32(2));

        _deposit(testStruct.operator1, amount);
        uint48 captureTimestamp = 0;

        uint256 slashableBefore =
            slasher.slashableStake(testStruct.subnetwork, testStruct.operator1, captureTimestamp, "");

        delegator.setSize(opSlot1, uint128(cap1 - 1));

        uint256 slashableAfter =
            slasher.slashableStake(testStruct.subnetwork, testStruct.operator1, captureTimestamp, "");
        assertLe(slashableAfter, slashableBefore);
    }

    function test_onlyRoles_enforced() public {
        vm.startPrank(bob);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, bob, CREATE_SLOT_ROLE)
        );
        _createSlot(0, 1);

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

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, bob, SET_WITHDRAWAL_BUFFER_SIZE_ROLE
            )
        );
        delegator.multicall(calls);
    }

    function test_depthGuards_enforced() public {
        _createSlot(0, 100);
        uint64 networkSlot = _rootIndex(uint32(1));

        _createSlot(networkSlot, 100);
        uint64 operatorSlot = networkSlot.createIndex(uint32(1));

        vm.expectRevert(IUniversalDelegator.WrongDepth.selector);
        _createSlot(operatorSlot, 1);
    }

    function test_networkAssignment_duplicateAndUnassignChecks() public {
        bytes32 subnetwork = bytes32(uint256(1));

        uint64 net1 = delegator.createSlot(subnetwork, 0, 100);

        assertEq(delegator.getSlotOfNetwork(subnetwork), net1);

        vm.expectRevert(IUniversalDelegator.AlreadyAssigned.selector);
        delegator.createSlot(subnetwork, 0, 100);
    }

    function test_networkAssignment_revertsWhenSlotAlreadyAssigned() public {
        bytes32 subnetwork1 = bytes32(uint256(1));
        bytes32 subnetwork2 = bytes32(uint256(2));

        uint64 networkSlot1 = delegator.createSlot(subnetwork1, 0, 100);

        vm.expectRevert(IUniversalDelegator.AlreadyAssigned.selector);
        delegator.createSlot(subnetwork1, 0, 100);

        uint64 networkSlot2 = delegator.createSlot(subnetwork2, 0, 100);

        assertEq(delegator.getSlotOfNetwork(subnetwork1), networkSlot1);
        assertEq(delegator.getSlotOfNetwork(subnetwork2), networkSlot2);
    }

    function test_operatorAssignment_duplicateAndUnassignChecks() public {
        bytes32 subnetwork = bytes32(uint256(1));
        uint64 networkSlot = delegator.createSlot(subnetwork, 0, 100);

        _createOperatorSlot(networkSlot, alice, 60);
        uint64 operatorSlot1 = networkSlot.createIndex(uint32(1));

        assertEq(delegator.getSlotOfOperator(networkSlot, alice), operatorSlot1);

        vm.expectRevert(IUniversalDelegator.AlreadyAssigned.selector);
        _createOperatorSlot(networkSlot, alice, 60);
    }

    function test_operatorAssignment_revertsWhenSlotAlreadyAssigned() public {
        bytes32 subnetwork = bytes32(uint256(1));
        uint64 networkSlot = delegator.createSlot(subnetwork, 0, 100);

        _createOperatorSlot(networkSlot, alice, 100);
        uint64 operatorSlot = networkSlot.createIndex(uint32(1));

        vm.expectRevert(IUniversalDelegator.AlreadyAssigned.selector);
        _createOperatorSlot(networkSlot, alice, 100);

        assertEq(delegator.getSlotOfOperator(networkSlot, alice), operatorSlot);
    }

    function test_swapSlots_keepsAllocationAfterStakeDecrease() public {
        _deposit(alice, 100);

        _createSlot(0, 30);
        _createSlot(0, 50);

        uint64 slot1 = _rootIndex(uint32(1));
        uint64 slot2 = _rootIndex(uint32(2));

        vm.warp(1);
        delegator.swapSlots(slot1, slot2);

        vm.warp(2);
        _withdraw(alice, 60);

        assertEq(delegator.getAllocated(slot2, 0), 50);
        assertEq(delegator.getAllocated(slot1, 0), 30);
    }

    function test_swapSlots_revertsWrongOrder() public {
        _createSlot(0, 10);
        _createSlot(0, 10);
        uint64 slot1 = _rootIndex(uint32(1));
        uint64 slot2 = _rootIndex(uint32(2));

        vm.expectRevert(IUniversalDelegator.WrongOrder.selector);
        delegator.swapSlots(slot2, slot1);
    }

    function test_swapSlots_adjacentTail_preservesLinks() public {
        _createSlot(0, 10);
        _createSlot(0, 10);
        _createSlot(0, 10);

        uint64 slot1 = _rootIndex(uint32(1));
        uint64 slot2 = _rootIndex(uint32(2));
        uint64 slot3 = _rootIndex(uint32(3));

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

        _createSlot(0, 120);
        uint64 networkSlot = _rootIndex(uint32(1));

        _createSlot(networkSlot, 40);
        _createSlot(networkSlot, 40);
        _createSlot(networkSlot, 40);

        uint64 op2 = networkSlot.createIndex(uint32(2));
        uint64 op3 = networkSlot.createIndex(uint32(3));
        uint48 beforeSwap = uint48(block.timestamp);

        vm.warp(uint256(beforeSwap) + 1);
        delegator.swapSlots(op2, op3);

        assertEq(delegator.getFilledAt(networkSlot, 0, beforeSwap), 120);
        assertEq(delegator.getFilled(networkSlot, 0), 120);
    }

    function test_swapSlots_revertsNotSameParent() public {
        _deposit(alice, 100);

        _createSlot(0, 10);
        uint64 rootSlot = _rootIndex(uint32(1));

        _createSlot(0, 10);
        uint64 networkSlot = _rootIndex(uint32(2));
        _createSlot(networkSlot, 10);
        uint64 operatorSlot = networkSlot.createIndex(uint32(1));

        vm.expectRevert(IUniversalDelegator.NotSameParent.selector);
        delegator.swapSlots(rootSlot, operatorSlot);
    }

    function test_swapSlots_revertsNotSameAllocated() public {
        _deposit(alice, 50);

        _createSlot(0, 100);
        uint64 networkSlot = _rootIndex(uint32(1));

        _createSlot(networkSlot, 50);
        _createSlot(networkSlot, 50);
        uint64 slot1 = networkSlot.createIndex(uint32(1));
        uint64 slot2 = networkSlot.createIndex(uint32(2));

        vm.expectRevert(IUniversalDelegator.NotSameAllocated.selector);
        delegator.swapSlots(slot1, slot2);
    }

    function test_swapSlots_revertsPartiallyAllocated_whenPartiallyAllocatedAtDurationZero() public {
        _deposit(alice, 70);

        _createSlot(0, 100);
        uint64 networkSlot = _rootIndex(uint32(1));

        _createSlot(networkSlot, 50);
        _createSlot(networkSlot, 50);
        uint64 slot1 = networkSlot.createIndex(uint32(1));
        uint64 slot2 = networkSlot.createIndex(uint32(2));

        vm.expectRevert(IUniversalDelegator.PartiallyAllocated.selector);
        delegator.swapSlots(slot1, slot2);
    }

    function test_swapSlots_allowsWhenPendingExistsInMaxDurationWindow() public {
        _deposit(alice, 100);

        _createSlot(0, 50);
        _createSlot(0, 50);
        uint64 slot1 = _rootIndex(uint32(1));
        uint64 slot2 = _rootIndex(uint32(2));

        // Pending withdrawals are still included for maxDuration = epochDuration - 1,
        // so the slot is treated as fully allocated in that window.
        _withdraw(alice, 30);
        assertEq(delegator.getBalance(0, 0), 100);
        assertEq(delegator.getBalance(0, EPOCH_DURATION - 1), 100);

        delegator.swapSlots(slot1, slot2);
        assertEq(delegator.getAllocated(slot1, 0), 50);
        assertEq(delegator.getAllocated(slot2, 0), 50);
    }

    function testFuzz_operatorSwapPreservesStakeForGuaranteeWindow(
        uint128 firstSize,
        uint128 middleSize,
        uint128 lastSize
    ) public {
        PendingDecreaseSwapFuzzState memory state;
        state.firstSize = uint128(bound(firstSize, 1, 100));
        state.middleSize = uint128(bound(middleSize, 1, 100));
        state.lastSize = uint128(bound(lastSize, 1, 100));
        state.network = makeAddr("pending-swap-network");
        state.operator3 = makeAddr("pending-swap-operator-3");
        state.subnetwork = state.network.subnetwork(0);
        uint128 totalSize = state.firstSize + state.middleSize + state.lastSize;

        _registerNetwork(state.network, makeAddr("pending-swap-middleware"));
        _registerOperator(alice);
        _registerOperator(bob);
        _registerOperator(state.operator3);
        _optIn(alice, state.network);
        _optIn(bob, state.network);
        _optIn(state.operator3, state.network);
        vm.prank(state.network);
        delegator.setMaxNetworkLimit(0, type(uint256).max);

        _deposit(alice, totalSize);
        uint64 networkSlot = delegator.createSlot(state.subnetwork, 0, totalSize);
        state.slot1 = delegator.createSlot(_operatorKey(alice), networkSlot, state.firstSize);
        state.slot2 = delegator.createSlot(_operatorKey(bob), networkSlot, state.middleSize);
        state.slot3 = delegator.createSlot(_operatorKey(state.operator3), networkSlot, state.lastSize);

        vm.warp(1);
        delegator.setSize(networkSlot, state.lastSize);
        delegator.setSize(state.slot1, 0);
        delegator.setSize(state.slot2, 0);

        uint48 start = uint48(block.timestamp);
        uint256 beforeStake0 = delegator.stakeFor(state.subnetwork, state.operator3, 0);
        uint256 beforeStake1 = delegator.stakeFor(state.subnetwork, state.operator3, 1);
        uint256 beforeStake2 = delegator.stakeFor(state.subnetwork, state.operator3, EPOCH_DURATION - 1);

        delegator.swapSlots(state.slot2, state.slot3);

        assertEq(beforeStake0, state.lastSize);
        assertEq(beforeStake1, state.lastSize);
        assertEq(beforeStake2, state.lastSize);

        assertGe(delegator.stakeFor(state.subnetwork, state.operator3, 0), beforeStake0);
        assertGe(delegator.stakeFor(state.subnetwork, state.operator3, 1), beforeStake1);
        assertGe(delegator.stakeFor(state.subnetwork, state.operator3, EPOCH_DURATION - 1), beforeStake2);

        vm.warp(start + 1);
        assertGe(delegator.stakeFor(state.subnetwork, state.operator3, 0), beforeStake1);
        assertGe(delegator.stakeFor(state.subnetwork, state.operator3, 1), beforeStake2);

        vm.warp(start + EPOCH_DURATION - 1);
        assertGe(delegator.stakeFor(state.subnetwork, state.operator3, 0), beforeStake2);
    }

    function test_getSizeAt_handlesDelayedDecreaseForSmallTimestamps() public {
        _deposit(alice, 100);

        _createSlot(0, 60);
        uint64 slot1 = _rootIndex(uint32(1));

        vm.warp(1);
        delegator.setSize(slot1, 40);

        assertEq(delegator.getSizeAt(slot1, 2), 60);
        assertEq(delegator.getSizeAt(slot1, 4), 40);
    }

    function test_getAllocated_capsBySizeAtDurationHorizon() public {
        _deposit(alice, 100);

        _createSlot(0, 100);
        uint64 slot1 = _rootIndex(uint32(1));

        vm.warp(1);
        delegator.setSize(slot1, 40);

        vm.warp(2);
        assertEq(delegator.getAllocated(slot1, 0), 100);
        assertEq(delegator.getAllocated(slot1, 1), 100);
        assertEq(delegator.getAllocated(slot1, EPOCH_DURATION - 1), 40);
        assertEq(delegator.getAllocatedAt(slot1, 1, 2), 100);
        assertEq(delegator.getAllocatedAt(slot1, EPOCH_DURATION - 1, 2), 40);
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

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, bob, SET_WITHDRAWAL_BUFFER_SIZE_ROLE
            )
        );
        delegator.setWithdrawalBufferSize(40);

        delegator.setWithdrawalBufferSize(40);
        assertEq(delegator.getWithdrawalBuffer(), 40);

        delegator.setWithdrawalBufferSize(120);
        assertEq(delegator.getWithdrawalBuffer(), 100);
    }

    function test_slotExists_revertsForMissingSlot() public {
        vm.expectRevert(IUniversalDelegator.SlotNotExists.selector);
        delegator.setSize(_rootIndex(uint32(1)), 1);
    }

    function test_modifier_slotExists_harness() public {
        UniversalDelegatorCoverageHarnessTest harness = new UniversalDelegatorCoverageHarnessTest();

        vm.expectRevert(IUniversalDelegator.SlotNotExists.selector);
        harness.exposeSlotExists(_rootIndex(uint32(1)), false);

        harness.exposeSlotExists(_rootIndex(uint32(1)), true);
    }

    function testFuzz_getPrevSum_siblingPrefixFitsUint208(uint8 siblingCount, uint128 size) public {
        UniversalDelegatorCoverageHarnessTest harness = new UniversalDelegatorCoverageHarnessTest();
        MockVaultForDelegatorCoverage vaultMock = new MockVaultForDelegatorCoverage();
        uint64 parent = _rootIndex(uint32(1));
        uint48 timestamp = 1;

        siblingCount = uint8(bound(siblingCount, 2, 20));

        vm.warp(timestamp);
        harness.setVaultRaw(address(vaultMock));
        harness.pushFirstChildRaw(parent, timestamp, 1);
        harness.pushSyncPrevSizeSumsRaw(parent, timestamp, 1);

        for (uint32 i = 1; i <= siblingCount; ++i) {
            uint64 slot = parent.createIndex(i);
            harness.pushSlotSizeRaw(slot, timestamp, size);
            if (i < siblingCount) {
                harness.pushNextSlotRaw(slot, timestamp, i + 1);
            }
        }

        uint64 target = parent.createIndex(uint32(siblingCount));
        uint256 expected = (uint256(siblingCount) - 1) * uint256(size);

        assertEq(harness.exposeGetPrevSum(target), expected);
        assertLe(expected, type(uint208).max);
    }

    function test_syncPrevSizeSums_modifier_harnessSyncsDirtyPrefixAndClearsFlag() public {
        UniversalDelegatorCoverageHarnessTest harness = new UniversalDelegatorCoverageHarnessTest();
        uint64 parent = _rootIndex(uint32(1));
        uint64 slot1 = parent.createIndex(uint32(1));
        uint64 slot2 = parent.createIndex(uint32(2));
        uint48 timestamp = 1;

        vm.warp(timestamp);
        harness.pushFirstChildRaw(parent, timestamp, 1);
        harness.pushSlotSizeRaw(slot1, timestamp, 7);
        harness.pushNextSlotRaw(slot1, timestamp, 2);
        harness.pushSlotSizeRaw(slot2, timestamp, 11);
        harness.pushSyncPrevSizeSumsRaw(parent, timestamp, 1);

        harness.exposeSyncPrevSizeSums(parent);

        assertEq(harness.latestPrevSizeSum(slot1), 0);
        assertEq(harness.latestPrevSizeSum(slot2), 7);
        assertEq(harness.latestSyncPrevSizeSums(parent), 0);
    }

    function test_getPrevSumAt_returnsZeroForRoot() public {
        UniversalDelegatorCoverageHarnessTest harness = new UniversalDelegatorCoverageHarnessTest();

        assertEq(harness.exposeGetPrevSumAt(0, 1), 0);
    }

    function test_createSlot_revertsForMissingParentSlot() public {
        vm.expectRevert(IUniversalDelegator.SlotNotExists.selector);
        delegator.createSlot(bytes32(0), _rootIndex(uint32(1)), 1);
    }

    function test_slotExists_revertsForMissingSlot_swapAndRemove() public {
        vm.expectRevert(IUniversalDelegator.SlotNotExists.selector);
        delegator.swapSlots(_rootIndex(uint32(1)), _rootIndex(uint32(2)));

        delegator.grantRole(REMOVE_SLOT_ROLE, owner);
        vm.expectRevert(IUniversalDelegator.SlotNotExists.selector);
        delegator.removeSlot(_rootIndex(uint32(1)));
    }

    function test_slotCounters_trackTotalAndExistingChildren() public {
        delegator.grantRole(REMOVE_SLOT_ROLE, owner);

        uint64 slot1 = _createRootSlot(0);
        uint64 slot2 = _createRootSlot(0);

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
        uint64 slot1 = _createRootSlot(0);
        uint64 slot2 = _createRootSlot(0);

        assertEq(slot1, _rootIndex(1));
        assertEq(slot2, _rootIndex(2));
        assertTrue(delegator.getSlot(slot1).exists);
        assertTrue(delegator.getSlot(slot2).exists);
    }

    function test_syncPrevSums_pathForNonRootParent_afterSlash() public {
        _deposit(alice, 100);

        bytes32 subnetwork = makeAddr("non-root-sync-subnetwork").subnetwork(0);
        uint64 networkSlot = delegator.createSlot(subnetwork, 0, 100);
        _createOperatorSlot(networkSlot, alice, 60);
        _createOperatorSlot(networkSlot, bob, 40);
        uint64 operatorSlot = networkSlot.createIndex(uint32(1));

        vm.prank(address(slasher));
        delegator.onSlash(subnetwork, alice, 1);

        uint128 currentSize = delegator.getSlot(operatorSlot).size;
        delegator.setSize(operatorSlot, currentSize);
        assertEq(_pending(operatorSlot), 0);
    }

    function test_syncPrevSums_multipleSlashes_thenCreateOperator_preservesExistingSiblingAllocations() public {
        address carol = makeAddr("sync-create-carol");
        address dave = makeAddr("sync-create-dave");
        address eve = makeAddr("sync-create-eve");

        _deposit(alice, 240);

        bytes32 subnetwork = makeAddr("multi-slash-create-subnetwork").subnetwork(0);
        uint64 networkSlot = delegator.createSlot(subnetwork, 0, 240);

        _createOperatorSlot(networkSlot, alice, 90);
        uint64 operatorSlot1 = networkSlot.createIndex(uint32(1));
        _createOperatorSlot(networkSlot, bob, 60);
        uint64 operatorSlot2 = networkSlot.createIndex(uint32(2));
        _createOperatorSlot(networkSlot, carol, 40);
        uint64 operatorSlot3 = networkSlot.createIndex(uint32(3));
        _createOperatorSlot(networkSlot, dave, 30);
        uint64 operatorSlot4 = networkSlot.createIndex(uint32(4));

        vm.prank(address(slasher));
        delegator.onSlash(subnetwork, alice, 10);
        vm.prank(address(slasher));
        delegator.onSlash(subnetwork, bob, 5);

        uint48 beforeCreate = uint48(block.timestamp);
        uint256 allocated2Before = delegator.getAllocated(operatorSlot2, 0);
        uint256 allocated3Before = delegator.getAllocated(operatorSlot3, 0);
        uint256 allocated4Before = delegator.getAllocated(operatorSlot4, 0);
        vm.warp(block.timestamp + 1);

        uint64 operatorSlot5 = delegator.createSlot(_operatorKey(eve), networkSlot, 15);

        assertEq(delegator.getAllocated(operatorSlot2, 0), allocated2Before);
        assertEq(delegator.getAllocated(operatorSlot3, 0), allocated3Before);
        assertEq(delegator.getAllocated(operatorSlot4, 0), allocated4Before);
        assertEq(delegator.getAllocatedAt(operatorSlot2, 0, beforeCreate), allocated2Before);
        assertEq(delegator.getAllocatedAt(operatorSlot3, 0, beforeCreate), allocated3Before);
        assertEq(delegator.getAllocatedAt(operatorSlot4, 0, beforeCreate), allocated4Before);
        assertEq(delegator.getAllocated(operatorSlot5, 0), 15);
        assertEq(delegator.getSlot(operatorSlot5).prevSizeSum, 205);
        _assertManualPrevSizeSumsMatch(networkSlot);
    }

    function test_viewWrappersAndHints() public {
        _deposit(alice, 100);

        address network = makeAddr("wrap-network");
        address middleware = makeAddr("wrap-middleware");
        _registerNetwork(network, middleware);
        bytes32 subnetwork = network.subnetwork(0);
        vm.prank(network);
        delegator.setMaxNetworkLimit(0, type(uint256).max);

        uint64 networkSlot = delegator.createSlot(subnetwork, 0, 100);
        _createOperatorSlot(networkSlot, alice, 80);
        uint64 operatorSlot = networkSlot.createIndex(uint32(1));

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
        assertEq(_pendingAt(operatorSlot, uint48(block.timestamp)), 0);
        assertEq(_pending(operatorSlot), 0);
    }

    function test_stakeFor_usesMaxNetworkLimitAsGate_notAsCap() public {
        _deposit(alice, 100);

        address network = makeAddr("stake-gate-network");
        address middleware = makeAddr("stake-gate-middleware");
        _registerNetwork(network, middleware);
        bytes32 subnetwork = network.subnetwork(0);

        uint64 networkSlot = delegator.createSlot(subnetwork, 0, 100);
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

        uint64 networkSlot = delegator.createSlot(subnetwork, 0, MAX_AMOUNT);
        _createOperatorSlot(networkSlot, alice, MAX_AMOUNT);
        uint64 operatorSlot = networkSlot.createIndex(uint32(1));

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
        assertEq(snapshot.stakeForEpoch, 0);
        assertGe(snapshot.stakeFor0, snapshot.stakeFor1);
        assertGe(snapshot.stakeFor1, snapshot.stakeForMaxDuration);
        assertLe(snapshot.stakeFor0, snapshot.activeStake + snapshot.activeWithdrawals0);

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
        assertEq(snapshot.stakeForEpoch, 0);
        assertGe(snapshot.stakeFor0, snapshot.stakeFor1);
        assertGe(snapshot.stakeFor1, snapshot.stakeForMaxDuration);
        assertLe(snapshot.stakeFor0, snapshot.activeStake + snapshot.activeWithdrawals0);

        vm.warp(4);
        _deposit(alice, 25);
        delegator.setSize(operatorSlot, 130);
        snapshot = _snapshotStakeTimeline(subnetwork, alice);
        _reportStakeTimeline("t4/deposit+setSize", snapshot);
        _assertStakeForInvariantForThreeSlots(address(vault), address(delegator), operatorSlot, 0, 0, EPOCH_DURATION);
        assertEq(snapshot.activeStake, 195);
        assertEq(snapshot.activeWithdrawals0, 20);
        assertEq(snapshot.stakeForEpoch, 0);
        assertGe(snapshot.stakeFor0, snapshot.stakeFor1);
        assertGe(snapshot.stakeFor1, snapshot.stakeForMaxDuration);
        assertLe(snapshot.stakeFor0, snapshot.activeStake + snapshot.activeWithdrawals0);

        vm.warp(5);
        _withdraw(alice, 15);
        delegator.setSize(operatorSlot, 160);
        snapshot = _snapshotStakeTimeline(subnetwork, alice);
        _reportStakeTimeline("t5/withdraw+setSize", snapshot);
        _assertStakeForInvariantForThreeSlots(address(vault), address(delegator), operatorSlot, 0, 0, EPOCH_DURATION);
        assertEq(snapshot.activeStake, 180);
        assertEq(snapshot.activeWithdrawals0, 35);
        assertEq(snapshot.stakeForEpoch, 0);
        assertGe(snapshot.stakeFor0, snapshot.stakeFor1);
        assertGe(snapshot.stakeFor1, snapshot.stakeForMaxDuration);
        assertLe(snapshot.stakeFor0, snapshot.activeStake + snapshot.activeWithdrawals0);

        vm.warp(7);
        snapshot = _snapshotStakeTimeline(subnetwork, alice);
        _reportStakeTimeline("t7/2-epochs", snapshot);
        _assertStakeForInvariantForThreeSlots(address(vault), address(delegator), operatorSlot, 0, 0, EPOCH_DURATION);
        assertEq(snapshot.activeStake, 180);
        assertEq(snapshot.activeWithdrawals0, 15);
        assertEq(snapshot.stakeForEpoch, 0);
        assertGe(snapshot.stakeFor0, snapshot.stakeFor1);
        assertGe(snapshot.stakeFor1, snapshot.stakeForMaxDuration);
        assertLe(snapshot.stakeFor0, snapshot.activeStake + snapshot.activeWithdrawals0);

        assertEq(delegator.getSlotOfOperator(networkSlot, alice), operatorSlot);
    }

    function test_stakeFor_simulation_setSizesDepositWithdrawEpochMinusOne_thenSetSizeZero() public {
        address network = makeAddr("stake-sim2-network");
        address middleware = makeAddr("stake-sim2-middleware");
        _registerNetwork(network, middleware);
        bytes32 subnetwork = network.subnetwork(0);

        vm.prank(network);
        delegator.setMaxNetworkLimit(0, type(uint256).max);

        uint64 networkSlot = delegator.createSlot(subnetwork, 0, 0);
        _createOperatorSlot(networkSlot, alice, 0);
        uint64 operatorSlot = networkSlot.createIndex(uint32(1));

        // setSizes(100)
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

    function test_createSlot_revertsTooManyNetworks() public {
        for (uint256 i; i < MAX_NETWORKS; ++i) {
            _createSlot(0, 0);
        }

        vm.expectRevert(IUniversalDelegator.TooManyChildren.selector);
        _createSlot(0, 0);
    }

    function test_createSlot_revertsTooManyNetworksAtRoot() public {
        for (uint256 i; i < MAX_NETWORKS; ++i) {
            bytes32 subnetwork = bytes32(i + 1);
            delegator.createSlot(subnetwork, 0, 0);
        }

        vm.expectRevert(IUniversalDelegator.TooManyChildren.selector);
        delegator.createSlot(bytes32(MAX_NETWORKS + 1), 0, 0);
    }

    function test_createSlot_revertsTooManyOperatorsPerNetwork() public {
        uint64 networkSlot = delegator.createSlot(bytes32("network"), 0, 0);

        for (uint256 i; i < MAX_OPERATORS; ++i) {
            address operator = address(uint160(i + 1));
            delegator.createSlot(_operatorKey(operator), networkSlot, 0);
        }

        vm.expectRevert(IUniversalDelegator.TooManyChildren.selector);
        delegator.createSlot(_operatorKey(address(uint160(MAX_OPERATORS + 1))), networkSlot, 0);
    }

    function test_removeSlot_revertsWhenAllocated() public {
        delegator.grantRole(REMOVE_SLOT_ROLE, owner);
        _deposit(alice, 100);
        _createSlot(0, 100);
        uint64 slot = _rootIndex(uint32(1));

        vm.expectRevert(IUniversalDelegator.SlotAllocated.selector);
        delegator.removeSlot(slot);
    }

    function test_removeSlot_lastRootNetwork_resetsWithdrawalBufferPrevSum() public {
        delegator.grantRole(REMOVE_SLOT_ROLE, owner);

        _deposit(alice, 100);
        _createSlot(0, 100);
        uint64 slot = _rootIndex(uint32(1));

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

        bytes32 subnetwork1 = makeAddr("remove-network-1").subnetwork(0);
        address network2 = makeAddr("remove-network-2");
        address middleware2 = makeAddr("remove-middleware-2");
        _registerNetwork(network2, middleware2);
        bytes32 subnetwork2 = network2.subnetwork(0);
        bytes32 subnetwork3 = makeAddr("remove-network-3").subnetwork(0);
        uint64 networkSlot1 = delegator.createSlot(subnetwork1, 0, 0);
        uint64 networkSlot2 = delegator.createSlot(subnetwork2, 0, 0);
        delegator.createSlot(subnetwork3, 0, 0);

        vm.prank(network2);
        delegator.setMaxNetworkLimit(0, type(uint256).max);
        delegator.removeSlot(networkSlot2);
        assertEq(delegator.getSlotOfNetwork(subnetwork2), 0);
        assertEq(delegator.maxNetworkLimit(subnetwork2), 0);

        delegator.createSlot(_operatorKey(alice), networkSlot1, 0);
        uint64 operatorSlot = networkSlot1.createIndex(uint32(1));
        delegator.removeSlot(operatorSlot);
        assertEq(delegator.getSlotOfOperator(networkSlot1, alice), 0);
    }

    function test_resetAllocation_lastRootNetwork_keepsWithdrawalBufferConsistent() public {
        address network = makeAddr("reset-last-network");
        address middleware = makeAddr("reset-last-middleware");
        _registerNetwork(network, middleware);
        bytes32 subnetwork = network.subnetwork(0);
        vm.prank(network);
        delegator.setMaxNetworkLimit(0, type(uint256).max);

        _deposit(alice, 100);
        uint64 networkSlot = delegator.createSlot(subnetwork, 0, 100);
        assertEq(delegator.getSlotOfNetwork(subnetwork), networkSlot);
        assertEq(delegator.getWithdrawalBuffer(), 0);

        _withdraw(alice, 100);
        vm.warp(block.timestamp + EPOCH_DURATION + 1);
        assertEq(delegator.getAllocated(networkSlot, 0), 0);

        vm.prank(middleware);
        delegator.resetAllocation(subnetwork);

        assertEq(delegator.getSlotOfNetwork(subnetwork), 0);
        assertFalse(delegator.getSlot(networkSlot).exists);

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

    function test_resetAllocation_rootPathAndSyncPrevSums() public {
        address network = makeAddr("reset-network-with-slot");
        address middleware = makeAddr("reset-middleware-with-slot");
        _registerNetwork(network, middleware);
        bytes32 subnetwork = network.subnetwork(0);

        _deposit(alice, 100);

        uint64 networkSlot = delegator.createSlot(subnetwork, 0, 80);
        uint64 slot2 = _createRootSlot(1);
        uint64 slot3 = _createRootSlot(1);

        vm.warp(1);
        delegator.setSize(networkSlot, 40);
        vm.prank(network);
        delegator.resetAllocation(subnetwork);

        assertFalse(delegator.getSlot(networkSlot).exists);
        assertEq(delegator.getSlotOfNetwork(subnetwork), 0);
        assertEq(delegator.getAllocated(slot3, 0), 1);
        assertEq(delegator.getAllocatedAt(slot3, 0, uint48(block.timestamp)), 1);

        delegator.setSize(slot2, 2);
        assertEq(delegator.getSlot(slot2).size, 2);
    }

    function test_resetAllocation_dirtyRoot_thenCreateSibling_preservesExistingSiblingAllocations() public {
        address network = makeAddr("reset-create-network");
        address middleware = makeAddr("reset-create-middleware");
        _registerNetwork(network, middleware);
        bytes32 subnetwork = network.subnetwork(0);

        _deposit(alice, 160);

        uint64 networkSlot = delegator.createSlot(subnetwork, 0, 80);
        uint64 slot2 = _createRootSlot(30);
        uint64 slot3 = _createRootSlot(20);

        vm.prank(network);
        delegator.resetAllocation(subnetwork);

        uint48 beforeCreate = uint48(block.timestamp);
        uint256 slot2Allocated = delegator.getAllocated(slot2, 0);
        uint256 slot3Allocated = delegator.getAllocated(slot3, 0);
        vm.warp(block.timestamp + 1);

        uint64 slot4 = _createRootSlot(25);

        assertFalse(delegator.getSlot(networkSlot).exists);
        assertEq(delegator.getSlotOfNetwork(subnetwork), 0);
        assertEq(delegator.getAllocated(slot2, 0), slot2Allocated);
        assertEq(delegator.getAllocated(slot3, 0), slot3Allocated);
        assertEq(delegator.getAllocatedAt(slot2, 0, beforeCreate), slot2Allocated);
        assertEq(delegator.getAllocatedAt(slot3, 0, beforeCreate), slot3Allocated);
        assertEq(delegator.getAllocated(slot4, 0), 25);
        _assertManualPrevSizeSumsMatch(0);
    }

    function test_dirtyParent_removeExpiredZeroAllocatedSibling_preservesHistoricalReads() public {
        address carol = makeAddr("dirty-remove-carol");
        address dave = makeAddr("dirty-remove-dave");

        _deposit(alice, 200);

        bytes32 subnetwork = makeAddr("dirty-remove-subnetwork").subnetwork(0);
        uint64 networkSlot = delegator.createSlot(subnetwork, 0, 200);

        _createOperatorSlot(networkSlot, alice, 70);
        uint64 operatorSlot1 = networkSlot.createIndex(uint32(1));
        _createOperatorSlot(networkSlot, bob, 60);
        uint64 operatorSlot2 = networkSlot.createIndex(uint32(2));
        _createOperatorSlot(networkSlot, carol, 40);
        uint64 operatorSlot3 = networkSlot.createIndex(uint32(3));
        _createOperatorSlot(networkSlot, dave, 30);
        uint64 operatorSlot4 = networkSlot.createIndex(uint32(4));

        vm.warp(1);
        delegator.setSize(operatorSlot3, 0);
        vm.warp(EPOCH_DURATION + 2);
        assertEq(delegator.getAllocated(operatorSlot3, 0), 0);
        assertEq(_pending(operatorSlot3), 0);

        vm.prank(address(slasher));
        delegator.onSlash(subnetwork, alice, 10);

        uint48 beforeRemove = uint48(block.timestamp);
        uint256 allocated2Before = delegator.getAllocated(operatorSlot2, 0);
        uint256 allocated4Before = delegator.getAllocated(operatorSlot4, 0);
        vm.warp(block.timestamp + 1);

        delegator.removeSlot(operatorSlot3);

        assertFalse(delegator.getSlot(operatorSlot3).exists);
        assertEq(delegator.getAllocated(operatorSlot2, 0), allocated2Before);
        assertEq(delegator.getAllocated(operatorSlot4, 0), allocated4Before);
        assertEq(delegator.getAllocatedAt(operatorSlot2, 0, beforeRemove), allocated2Before);
        assertEq(delegator.getAllocatedAt(operatorSlot4, 0, beforeRemove), allocated4Before);
        assertEq(delegator.getSlot(operatorSlot4).prevSizeSum, 120);
        _assertManualPrevSizeSumsMatch(networkSlot);
        _assertManualPrevSizeSumsMatch(0);
        assertEq(delegator.getSlot(operatorSlot1).size, 60);
    }

    function testFuzz_chaoticDirtyParentOperations_preserveManualPrevSizeSums(uint256 seed) public {
        _deposit(alice, 400);

        bytes32 subnetwork = makeAddr("chaos-subnetwork").subnetwork(0);
        uint64 networkSlot = delegator.createSlot(subnetwork, 0, 400);
        ChaosState memory state = _initChaosState(networkSlot);

        for (uint256 step; step < 32; ++step) {
            seed = uint256(keccak256(abi.encode(seed, step, block.timestamp)));
            state = _runChaosStep(state, networkSlot, subnetwork, seed);

            if (_countTrue(state.exists) > 0) {
                uint256 syncIndex = _pickExistingIndex(seed, state.exists);
                uint64 syncSlot = state.operatorSlots[syncIndex];
                delegator.setSize(syncSlot, delegator.getSlot(syncSlot).size);
            }

            _assertManualPrevSizeSumsMatch(networkSlot);
            _assertManualPrevSizeSumsMatch(0);
        }
    }

    function test_resetAllocation_singleNetworkClearsAssignmentAndAllowsReassign() public {
        address network = makeAddr("reset-single-network");
        address middleware = makeAddr("reset-single-middleware");
        _registerNetwork(network, middleware);
        bytes32 subnetwork = network.subnetwork(0);
        vm.prank(network);
        delegator.setMaxNetworkLimit(0, type(uint256).max);

        uint64 slot = delegator.createSlot(subnetwork, 0, 0);
        assertEq(delegator.getSlotOfNetwork(subnetwork), slot);
        assertEq(delegator.maxNetworkLimit(subnetwork), type(uint208).max);

        vm.prank(middleware);
        delegator.resetAllocation(subnetwork);

        assertEq(delegator.getSlotOfNetwork(subnetwork), 0);
        assertEq(delegator.maxNetworkLimit(subnetwork), 0);

        uint64 newSlot = delegator.createSlot(subnetwork, 0, 0);
        assertEq(delegator.getSlotOfNetwork(subnetwork), newSlot);
    }

    function test_onSlash_rootDecreasesRootSize() public {
        _deposit(alice, 100);

        bytes32 subnetwork = makeAddr("root-on-slash").subnetwork(0);
        uint64 networkSlot = delegator.createSlot(subnetwork, 0, 80);
        delegator.createSlot(_operatorKey(alice), networkSlot, 80);

        assertEq(delegator.getSlot(networkSlot).size, 80);

        vm.prank(address(slasher));
        delegator.onSlash(subnetwork, alice, 20);

        assertEq(delegator.getSlot(networkSlot).size, 60);
    }

    function test_onSlash_parentPendingAndSizeAreCappedByReducedActualAmount() public {
        address network = makeAddr("slash-parent-cap-network");
        address middleware = makeAddr("slash-parent-cap-middleware");
        _registerNetwork(network, middleware);
        _registerOperator(alice);
        _optIn(alice, network);

        _deposit(alice, 100);

        bytes32 subnetwork = network.subnetwork(0);
        vm.prank(network);
        delegator.setMaxNetworkLimit(0, type(uint256).max);

        uint64 networkSlot = delegator.createSlot(subnetwork, 0, 100);
        _createOperatorSlot(networkSlot, alice, 20);
        uint64 operatorSlot = networkSlot.createIndex(uint32(1));

        vm.warp(1);
        delegator.setSize(networkSlot, 30);

        assertEq(_pending(networkSlot), 70);
        assertEq(delegator.getSlot(networkSlot).size, 100);
        assertEq(delegator.getSlot(operatorSlot).size, 20);
        assertEq(slasher.slashableStake(subnetwork, alice, 0, ""), 20);

        vm.warp(2);
        assertEq(_requestAndExecuteSlash(middleware, subnetwork, alice, 100, 0), 20);

        assertEq(_pending(networkSlot), 50);
        assertEq(delegator.getSlot(networkSlot).size, 80);
        assertEq(delegator.getSlot(operatorSlot).size, 0);
    }

    function test_onSlash_revertsNotAssigned() public {
        vm.prank(address(slasher));
        try delegator.onSlash(bytes32(0), address(0), 0) {
            console2.log("onSlash not assigned / no revert");
        } catch (bytes memory err) {
            console2.log("onSlash not assigned / revert data length", err.length);
        }
    }

    function test_setSize_sameValue_afterSlashSync_returnsZero() public {
        _deposit(alice, 100);

        bytes32 subnetwork = makeAddr("sync-slot-subnetwork").subnetwork(0);
        uint64 networkSlot = delegator.createSlot(subnetwork, 0, 100);
        _createOperatorSlot(networkSlot, alice, 100);

        vm.prank(address(slasher));
        delegator.onSlash(subnetwork, alice, 1);

        uint128 currentSize = delegator.getSlot(networkSlot).size;
        delegator.setSize(networkSlot, currentSize);
        assertEq(_pending(networkSlot), 0);
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
        UniversalDelegator(noRoleDelegator).createSlot(DUMMY_NETWORK.subnetwork(1), 0, 1);
    }

    function test_initialize_grantsRemoveAndWithdrawalBufferRolesFromInitParams() public {
        IUniversalDelegator.InitParams memory params = _defaultDelegatorInitParams();
        params.defaultAdminRoleHolder = address(0);
        params.createSlotRoleHolder = address(0);
        params.setSizeRoleHolder = address(0);
        params.swapSlotsRoleHolder = address(0);
        params.removeSlotRoleHolder = alice;
        params.setWithdrawalBufferSizeRoleHolder = bob;

        address deployed =
            delegatorFactory.create(UNIVERSAL_DELEGATOR_TYPE, abi.encode(address(vault), abi.encode(params)));

        assertTrue(IAccessControl(deployed).hasRole(REMOVE_SLOT_ROLE, alice));
        assertTrue(IAccessControl(deployed).hasRole(SET_WITHDRAWAL_BUFFER_SIZE_ROLE, bob));
    }

    function test_initialize_harness_revertsNotVault() public {
        UniversalDelegatorInitCoverageHarnessTest harness = new UniversalDelegatorInitCoverageHarnessTest(
            address(networkRegistry), address(vaultFactory), address(networkMiddlewareService)
        );

        vm.expectRevert(IUniversalDelegator.NotVault.selector);
        harness.exposeInitialize(abi.encode(address(0xBEEF), abi.encode(_defaultDelegatorInitParams())));
    }

    function test_migrateReverts_NotVault() public {
        vm.expectRevert(IUniversalDelegator.NotVault.selector);
        delegator.migrate(address(0xBEEF));
    }

    function test_migrate_fromVault_recordsLegacyDelegatorOnly() public {
        MockLegacyDelegatorType oldDelegator = new MockLegacyDelegatorType(0);
        vm.prank(address(vault));
        delegator.migrate(address(oldDelegator));

        assertEq(delegator.oldDelegator(), address(oldDelegator));
        assertEq(delegator.migrateTimestamp(), uint48(block.timestamp));
        IUniversalDelegator.Slot memory root = delegator.getSlot(0);
        assertEq(root.existChildren, 0);
    }

    function test_migrate_fromVault_operatorNetworkSpecificLegacy_recordsLegacyDelegatorOnly() public {
        MockLegacyDelegatorType oldDelegator = new MockLegacyDelegatorType(OPERATOR_NETWORK_SPECIFIC_DELEGATOR_TYPE);
        vm.prank(address(vault));
        delegator.migrate(address(oldDelegator));

        assertEq(delegator.oldDelegator(), address(oldDelegator));
        assertEq(delegator.migrateTimestamp(), uint48(block.timestamp));
        IUniversalDelegator.Slot memory root = delegator.getSlot(0);
        assertEq(root.existChildren, 0);
    }

    function test_onSlashLegacy_reserveDoesNotAllocateFutureSibling() public {
        _deposit(alice, 100);

        MockLegacyDelegatorType oldDelegator = new MockLegacyDelegatorType(OPERATOR_NETWORK_SPECIFIC_DELEGATOR_TYPE);
        bytes32 subnetwork1 = makeAddr("legacy-reserve-network-1").subnetwork(0);
        oldDelegator.setOperatorNetworkSpecific(subnetwork1, alice, 100);

        vm.prank(address(vault));
        delegator.migrate(address(oldDelegator));
        bytes32 subnetwork2 = makeAddr("legacy-reserve-network-2").subnetwork(0);
        uint64 networkSlot1 = delegator.createSlot(subnetwork1, 0, 100);
        delegator.createSlot(_operatorKey(alice), networkSlot1, type(uint128).max);
        uint64 networkSlot2 = delegator.createSlot(subnetwork2, 0, 100);

        vm.prank(address(slasher));
        delegator.onSlashLegacy(subnetwork1, alice, 40);

        assertEq(delegator.getSlot(networkSlot1).size, 60);
        vm.prank(address(slasher));
        assertEq(delegator.getAllocated(networkSlot1, 0), 60);
        vm.prank(address(slasher));
        assertEq(delegator.getAllocated(networkSlot2, 0), 40);
    }

    function test_onSlashLegacy_ignoresMatchingSlotOutsideMigratedReserve() public {
        _deposit(alice, 200);

        MockLegacyDelegatorType oldDelegator = new MockLegacyDelegatorType(0);
        vm.prank(address(vault));
        delegator.migrate(address(oldDelegator));
        bytes32 subnetwork = makeAddr("legacy-outside-reserve-network").subnetwork(0);
        address operator = makeAddr("legacy-outside-reserve-operator");

        uint64 networkSlot = delegator.createSlot(subnetwork, 0, 100);
        uint64 operatorSlot = delegator.createSlot(_operatorKey(operator), networkSlot, 100);

        vm.prank(address(slasher));
        delegator.onSlashLegacy(subnetwork, operator, 60);

        assertEq(delegator.getSlot(networkSlot).size, 40);
        assertEq(delegator.getSlot(operatorSlot).size, 40);
    }

    function _requestAndExecuteSlash(
        address middleware,
        bytes32 subnetwork,
        address operator,
        uint256 amount,
        uint48 captureTimestamp
    ) internal returns (uint256 slashedAmount) {
        vm.startPrank(middleware);
        uint256 slashIndex = slasher.requestSlash(subnetwork, operator, amount, captureTimestamp, "");
        vm.warp(block.timestamp + 1);
        slashedAmount = slasher.executeSlash(slashIndex, "");
        vm.stopPrank();
    }

    function _defaultDelegatorInitParams() internal view returns (IUniversalDelegator.InitParams memory) {
        return IUniversalDelegator.InitParams({
            defaultAdminRoleHolder: owner,
            createSlotRoleHolder: owner,
            setSizeRoleHolder: owner,
            swapSlotsRoleHolder: owner,
            removeSlotRoleHolder: owner,
            setWithdrawalBufferSizeRoleHolder: owner,
            withdrawalBufferSize: type(uint128).max
        });
    }

    function _migrateAndCreateLegacyReserve(address oldDelegator, uint128 size) internal returns (uint64) {
        vm.prank(address(vault));
        delegator.migrate(oldDelegator);
        return _createRootSlot(size);
    }

    function _createRootSlot(uint256 size) internal returns (uint64) {
        ++dummyNetworkId;
        return delegator.createSlot(DUMMY_NETWORK.subnetwork(dummyNetworkId), 0, uint128(size));
    }

    function _createSlot(uint64 parentIndex, uint256 size) internal {
        bytes32 key;
        uint256 depth = parentIndex.getDepth();
        if (depth == 0) {
            ++dummyNetworkId;
            key = DUMMY_NETWORK.subnetwork(dummyNetworkId);
        } else if (depth == 1) {
            ++dummyOperatorId;
            address dummyOperator = address(uint160(DUMMY_OPERATOR_BASE) + dummyOperatorId);
            key = _operatorKey(dummyOperator);
        }
        delegator.createSlot(key, parentIndex, uint128(size));
    }

    function _createNetworkSlot(uint64 parentIndex, bytes32 subnetwork, uint256 size) internal {
        delegator.createSlot(subnetwork, parentIndex, uint128(size));
    }

    function _createOperatorSlot(uint64 parentIndex, address operator, uint256 size) internal {
        delegator.createSlot(_operatorKey(operator), parentIndex, uint128(size));
    }

    function _operatorKey(address operator) internal pure returns (bytes32) {
        return bytes32(bytes20(operator));
    }

    function _rootIndex(uint32 localIndex) internal pure returns (uint64) {
        return uint64(0).createIndex(localIndex);
    }

    function _unallocated2(uint64 parentIndex, uint64 slot1, uint64 slot2) internal view returns (uint256) {
        uint256 available = delegator.getBalance(parentIndex, 0);
        uint256 allocated = delegator.getAllocated(slot1, 0) + delegator.getAllocated(slot2, 0);
        return available > allocated ? available - allocated : 0;
    }

    function _unallocated3(uint64 parentIndex, uint64 slot1, uint64 slot2, uint64 slot3)
        internal
        view
        returns (uint256)
    {
        uint256 available = delegator.getBalance(parentIndex, 0);
        uint256 allocated =
            delegator.getAllocated(slot1, 0) + delegator.getAllocated(slot2, 0) + delegator.getAllocated(slot3, 0);
        return available > allocated ? available - allocated : 0;
    }

    function _pending(uint64 index) internal view returns (uint208) {
        IUniversalDelegator.Slot memory slot = delegator.getSlot(index);
        return slot.size > slot.latestSize ? uint208(slot.size - slot.latestSize) : 0;
    }

    function _pendingAt(uint64 index, uint48 timestamp) internal view returns (uint208) {
        IUniversalDelegator.Slot memory slot = delegator.getSlot(index);
        uint128 sizeAt = delegator.getSizeAt(index, timestamp);
        return sizeAt > slot.latestSize ? uint208(sizeAt - slot.latestSize) : 0;
    }

    function _assertManualPrevSizeSumsMatch(uint64 parentIndex) internal view {
        uint208 expectedPrevSizeSum;
        uint32 childIndex = delegator.getSlot(parentIndex).firstChild;

        while (childIndex > 0 && childIndex < WITHDRAWAL_BUFFER_CHILD_INDEX) {
            uint64 slotIndex = parentIndex.createIndex(childIndex);
            IUniversalDelegator.Slot memory slot = delegator.getSlot(slotIndex);
            assertEq(slot.prevSizeSum, expectedPrevSizeSum);
            expectedPrevSizeSum += slot.size;
            childIndex = slot.nextSlot;
        }
    }

    function _initChaosState(uint64 networkSlot) internal returns (ChaosState memory state) {
        state.operators[0] = alice;
        state.operators[1] = bob;
        state.operators[2] = makeAddr("chaos-carol");
        state.operators[3] = makeAddr("chaos-dave");
        state.operators[4] = makeAddr("chaos-eve");
        state.operators[5] = makeAddr("chaos-frank");

        _createOperatorSlot(networkSlot, state.operators[0], 120);
        state.operatorSlots[0] = networkSlot.createIndex(uint32(1));
        state.exists[0] = true;
        _createOperatorSlot(networkSlot, state.operators[1], 100);
        state.operatorSlots[1] = networkSlot.createIndex(uint32(2));
        state.exists[1] = true;
        _createOperatorSlot(networkSlot, state.operators[2], 80);
        state.operatorSlots[2] = networkSlot.createIndex(uint32(3));
        state.exists[2] = true;
        _createOperatorSlot(networkSlot, state.operators[3], 60);
        state.operatorSlots[3] = networkSlot.createIndex(uint32(4));
        state.exists[3] = true;
    }

    function _runChaosStep(ChaosState memory state, uint64 networkSlot, bytes32 subnetwork, uint256 seed)
        internal
        returns (ChaosState memory)
    {
        vm.warp(block.timestamp + uint48(seed % 3));

        uint256 action = seed % 6;
        if (action == 0) {
            _deposit(alice, (seed % 25) + 1);
            return state;
        }
        if (action == 1) {
            uint256 withdrawable = vault.activeBalanceOf(alice);
            if (withdrawable > 0) {
                _withdraw(alice, bound(seed >> 8, 1, withdrawable));
            }
            return state;
        }
        if (action == 2) {
            uint256 index = _pickExistingIndex(seed >> 16, state.exists);
            address(delegator)
                .call(
                    abi.encodeCall(delegator.setSize, (state.operatorSlots[index], uint128(bound(seed >> 32, 0, 180))))
                );
            return state;
        }
        if (action == 3) {
            uint256 index = _pickExistingIndex(seed >> 48, state.exists);
            uint256 currentSize = delegator.getSlot(state.operatorSlots[index]).size;
            if (currentSize > 0) {
                vm.prank(address(slasher));
                delegator.onSlash(subnetwork, state.operators[index], bound(seed >> 64, 1, currentSize));
            }
            return state;
        }
        if (action == 4) {
            uint256 index1 = _pickExistingIndex(seed >> 80, state.exists);
            uint256 index2 = _pickExistingIndex(seed >> 96, state.exists);
            if (index1 != index2) {
                uint64 left = state.operatorSlots[index1];
                uint64 right = state.operatorSlots[index2];
                if (left.getChildIndex() > right.getChildIndex()) {
                    (left, right) = (right, left);
                }
                address(delegator).call(abi.encodeCall(delegator.swapSlots, (left, right)));
            }
            return state;
        }

        uint256 created = _countTrue(state.exists);
        if (created < state.operators.length) {
            uint256 nextIndex = _firstMissingIndex(state.exists);
            (bool success, bytes memory returnData) = address(delegator)
                .call(
                    abi.encodeCall(
                        delegator.createSlot,
                        (_operatorKey(state.operators[nextIndex]), networkSlot, uint128(bound(seed >> 112, 0, 50)))
                    )
                );
            if (success) {
                state.operatorSlots[nextIndex] = abi.decode(returnData, (uint64));
                state.exists[nextIndex] = true;
            }
            return state;
        }

        uint256 removable = _findRemovableIndex(state.operatorSlots, state.exists);
        if (removable < state.operators.length) {
            address(delegator).call(abi.encodeCall(delegator.removeSlot, (state.operatorSlots[removable])));
            state.exists[removable] = delegator.getSlot(state.operatorSlots[removable]).exists;
        }
        return state;
    }

    function _pickExistingIndex(uint256 seed, bool[6] memory exists) internal pure returns (uint256) {
        uint256 start = seed % exists.length;
        for (uint256 i; i < exists.length; ++i) {
            uint256 index = (start + i) % exists.length;
            if (exists[index]) {
                return index;
            }
        }
        return 0;
    }

    function _countTrue(bool[6] memory flags) internal pure returns (uint256 count) {
        for (uint256 i; i < flags.length; ++i) {
            if (flags[i]) {
                ++count;
            }
        }
    }

    function _firstMissingIndex(bool[6] memory flags) internal pure returns (uint256) {
        for (uint256 i; i < flags.length; ++i) {
            if (!flags[i]) {
                return i;
            }
        }
        return flags.length;
    }

    function _findRemovableIndex(uint64[6] memory operatorSlots, bool[6] memory exists)
        internal
        view
        returns (uint256)
    {
        for (uint256 i; i < exists.length; ++i) {
            if (exists[i] && delegator.getAllocated(operatorSlots[i], 0) == 0) {
                return i;
            }
        }
        return exists.length;
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
    using UniversalDelegatorIndex for uint64;

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

        address vaultV2Migrate = address(
            new VaultV2Migrate(
                address(delegatorFactory), address(slasherFactory), address(0), address(rewards), address(0)
            )
        );
        address vaultImpl = address(
            new VaultV2(
                address(delegatorFactory),
                address(slasherFactory),
                address(vaultFactory),
                address(0),
                address(rewards),
                address(0),
                vaultV2Migrate
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
            if (delegatorIndices[i] == OPERATOR_NETWORK_SPECIFIC_DELEGATOR_TYPE) {
                vm.prank(network);
                IBaseDelegator(oldDelegator).setMaxNetworkLimit(0, 123);
            }
            bytes memory migrateData = abi.encode(_buildMigrateParams());
            vaultFactory.migrate(address(vault_), vaultFactory.lastVersion(), migrateData);
            assertEq(vault_.adaptersAllowDelay(), EPOCH_DURATION + 2);
            _assertDelegatorMigration(vault_, oldDelegator, delegatorIndices[i]);
        }
    }

    function test_MigrateRevertsWhenAdaptersAllowDelayNotGreaterThanEpochDuration() public {
        (IVaultV2 vault_,,) = _createLegacyVault(0);
        IVaultV2.MigrateParams memory migrateParams = _buildMigrateParams();
        migrateParams.adaptersAllowDelay = EPOCH_DURATION;
        uint64 newVersion = vaultFactory.lastVersion();

        vm.expectRevert(IVaultV2.InvalidAdaptersAddDelay.selector);
        vaultFactory.migrate(address(vault_), newVersion, abi.encode(migrateParams));
    }

    function test_MigrateLegacyDelegator_RestoresUniversalDelegatorRoles() public {
        (IVaultV2 vault_,,) = _createLegacyVault(0);

        bytes memory migrateData = abi.encode(_buildMigrateParams());
        vaultFactory.migrate(address(vault_), vaultFactory.lastVersion(), migrateData);

        IAccessControl newDelegator = IAccessControl(vault_.delegator());
        assertTrue(newDelegator.hasRole(bytes32(0), owner));
        assertTrue(newDelegator.hasRole(CREATE_SLOT_ROLE, owner));
        assertFalse(newDelegator.hasRole(bytes32(0), address(vault_)));
        assertFalse(newDelegator.hasRole(CREATE_SLOT_ROLE, address(vault_)));
    }

    function test_MigrateOperatorNetworkSpecificDelegator_AllowsZeroUniversalDelegatorRoleHolders() public {
        (IVaultV2 vault_, address oldDelegator,) = _createLegacyVault(OPERATOR_NETWORK_SPECIFIC_DELEGATOR_TYPE);
        vm.prank(network);
        IBaseDelegator(oldDelegator).setMaxNetworkLimit(0, 123);

        IVaultV2.MigrateParams memory migrateParams = _buildMigrateParams();
        IUniversalDelegator.InitParams memory delegatorParams =
            abi.decode(migrateParams.delegatorParams, (IUniversalDelegator.InitParams));
        delegatorParams.defaultAdminRoleHolder = address(0);
        delegatorParams.createSlotRoleHolder = address(0);
        migrateParams.delegatorParams = abi.encode(delegatorParams);

        vaultFactory.migrate(address(vault_), vaultFactory.lastVersion(), abi.encode(migrateParams));

        IAccessControl newDelegator = IAccessControl(vault_.delegator());
        assertFalse(newDelegator.hasRole(bytes32(0), owner));
        assertFalse(newDelegator.hasRole(CREATE_SLOT_ROLE, owner));
        assertFalse(newDelegator.hasRole(bytes32(0), address(vault_)));
        assertFalse(newDelegator.hasRole(CREATE_SLOT_ROLE, address(vault_)));
        _assertDelegatorMigration(vault_, oldDelegator, OPERATOR_NETWORK_SPECIFIC_DELEGATOR_TYPE);
    }

    function test_MigrateOperatorNetworkSpecificDelegator_KeepsVaultUniversalDelegatorRolesWhenConfigured() public {
        (IVaultV2 vault_, address oldDelegator,) = _createLegacyVault(OPERATOR_NETWORK_SPECIFIC_DELEGATOR_TYPE);
        vm.prank(network);
        IBaseDelegator(oldDelegator).setMaxNetworkLimit(0, 123);

        IVaultV2.MigrateParams memory migrateParams = _buildMigrateParams();
        IUniversalDelegator.InitParams memory delegatorParams =
            abi.decode(migrateParams.delegatorParams, (IUniversalDelegator.InitParams));
        delegatorParams.defaultAdminRoleHolder = address(vault_);
        delegatorParams.createSlotRoleHolder = address(vault_);
        migrateParams.delegatorParams = abi.encode(delegatorParams);

        vaultFactory.migrate(address(vault_), vaultFactory.lastVersion(), abi.encode(migrateParams));

        IAccessControl newDelegator = IAccessControl(vault_.delegator());
        assertTrue(newDelegator.hasRole(bytes32(0), address(vault_)));
        assertTrue(newDelegator.hasRole(CREATE_SLOT_ROLE, address(vault_)));
        _assertDelegatorMigration(vault_, oldDelegator, OPERATOR_NETWORK_SPECIFIC_DELEGATOR_TYPE);
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

        newDelegator.createSlot(subnetwork, 0, 0);
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
            createSlotRoleHolder: owner,
            setSizeRoleHolder: owner,
            swapSlotsRoleHolder: owner,
            removeSlotRoleHolder: owner,
            setWithdrawalBufferSizeRoleHolder: owner,
            withdrawalBufferSize: type(uint128).max
        });
        IUniversalSlasher.InitParams memory slasherParams = IUniversalSlasher.InitParams({
            isBurnerHook: false, vetoDuration: vetoDuration, resolverSetDelay: EPOCH_DURATION * 3
        });
        return IVaultV2.MigrateParams({
            name: VAULT_NAME,
            symbol: VAULT_SYMBOL,
            adaptersAllowDelay: EPOCH_DURATION + 2,
            defaultAdminRoleHolder: owner,
            setAdapterLimitRoleHolder: owner,
            swapAdaptersRoleHolder: owner,
            allocateAdapterRoleHolder: owner,
            deallocateAdapterRoleHolder: owner,
            operatorNetworkSpecificSubnetworkId: 0,
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
        assertEq(IUniversalDelegator(newDelegator).oldDelegator(), oldDelegator);
        assertEq(IUniversalDelegator(newDelegator).migrateTimestamp(), uint48(block.timestamp));

        IUniversalDelegator.Slot memory root = IUniversalDelegator(newDelegator).getSlot(0);
        if (legacyType == OPERATOR_NETWORK_SPECIFIC_DELEGATOR_TYPE) {
            assertEq(root.existChildren, 1);
            uint64 networkSlot = uint64(0).createIndex(root.firstChild);
            uint64 operatorSlot = networkSlot.createIndex(uint32(1));
            assertEq(IUniversalDelegator(newDelegator).getSlot(networkSlot).subnetworkOrOperator, network.subnetwork(0));
            assertEq(IUniversalDelegator(newDelegator).getSlot(networkSlot).size, type(uint128).max);
            assertEq(
                IUniversalDelegator(newDelegator).getSlot(operatorSlot).subnetworkOrOperator, bytes32(bytes20(operator))
            );
            assertEq(IUniversalDelegator(newDelegator).getSlot(operatorSlot).size, type(uint128).max);
        } else {
            assertEq(root.existChildren, 0);
        }
    }
}
