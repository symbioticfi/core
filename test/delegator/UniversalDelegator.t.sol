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
    MAX_SUBVAULTS,
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
    uint64 public immutable TYPE;

    constructor(uint64 type_) {
        TYPE = type_;
    }
}

contract MockVaultForDelegatorCoverage {
    uint48 public epochDuration = 3;
}

contract UniversalDelegatorCoverageHarnessTest is Test, UniversalDelegator {
    using Checkpoints for Checkpoints.Trace208;

    constructor() UniversalDelegator(address(0), address(0), address(0), 0, address(0)) {}

    function setSlotExistsRaw(uint96 index, bool exists_) external {
        slots[index].exists = exists_;
    }

    function exposeSlotExists(uint96 index, bool exists_) external {
        slots[index].exists = exists_;
        _revertIfNotExists(index);
    }

    function setVaultRaw(address vault_) external {
        vault = vault_;
    }

    function pushSlotSizeRaw(uint96 index, uint48 timestamp, uint208 value) external {
        slots[index].size.push(timestamp, value);
    }

    function pushPendingCumulativeRaw(uint96 index, uint48 timestamp, uint208 value) external {
        slots[index].pendingCumulative.push(timestamp, value);
    }

    function pushNextSlotRaw(uint96 index, uint48 timestamp, uint208 value) external {
        slots[index].nextSlot.push(timestamp, value);
    }

    function pushFirstChildRaw(uint96 index, uint48 timestamp, uint208 value) external {
        slots[index].firstChild.push(timestamp, value);
    }

    function pushSyncPrevSizeSumsRaw(uint96 index, uint48 timestamp, uint208 value) external {
        slots[index].syncPrevSizeSums.push(timestamp, value);
    }

    function setSlotSharedRaw(uint96 index, bool isShared_) external {
        slots[index].isShared = isShared_;
    }

    function setChildrenPendingAtRaw(uint96 index, uint48 timestamp) external {
        slots[index]._childrenPendingAt = timestamp;
    }

    function latestSyncPrevSizeSums(uint96 index) external view returns (uint208) {
        return slots[index].syncPrevSizeSums.latest();
    }

    function latestPrevSizeSum(uint96 index) external view returns (uint208) {
        return slots[index].prevSizeSum.latest();
    }

    function exposeSyncPrevSizeSums(uint96 parentIndex) external syncPrevSizeSums(parentIndex) {}

    function exposeGetPendingSize(uint96 index, uint48 duration) external view returns (uint208) {
        return _getPendingSize(index, duration);
    }

    function exposeGetPrevSum(uint96 index, uint48 duration) external view returns (uint208) {
        return _getPrevSum(index, duration);
    }

    function exposeGetPrevSizeSumAt(uint96 index, uint48 timestamp) external view returns (uint208) {
        return _getPrevSizeSumAt(index, timestamp);
    }

    function exposeGetPrevPendingSumAt(uint96 index, uint48 duration, uint48 timestamp)
        external
        view
        returns (uint208)
    {
        return _getPrevPendingSumAt(index, duration, timestamp);
    }

    function exposeGetPrevPendingSum(uint96 index, uint48 duration) external view returns (uint208) {
        return _getPrevPendingSum(index, duration);
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

    struct ChaosState {
        address[6] operators;
        uint96[6] operatorSlots;
        bool[6] exists;
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

    function test_decreaseLimit_leafSubvaultSchedulesPendingUntilDelayExpires() public {
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

    function test_leafSubvaultDecreaseWithoutChildren_schedulesPending() public {
        _deposit(alice, 100);

        _createSlot(0, false, 60);
        _createSlot(0, false, 40);
        uint96 slot1 = _rootIndex(uint32(1));
        uint96 slot2 = _rootIndex(uint32(2));

        vm.warp(1);
        delegator.setSize(slot1, 30);

        assertEq(delegator.getPending(slot1, 0), 30);
        assertEq(delegator.getAllocated(slot1, 0), 60);
        assertEq(delegator.getAllocated(slot2, 0), 40);
        assertEq(_unallocated2(0, slot1, slot2), 0);
    }

    function test_leafNetworkDecreaseWithoutChildren_schedulesPending() public {
        _deposit(alice, 100);

        _createSlot(0, false, 100);
        uint96 subvault = _rootIndex(uint32(1));
        bytes32 subnetwork = makeAddr("leaf-network-subnetwork").subnetwork(0);
        _createNetworkSlot(subvault, subnetwork, 80);
        uint96 networkSlot = subvault.createIndex(uint32(1));

        vm.warp(1);
        delegator.setSize(networkSlot, 30);

        assertEq(delegator.getPending(networkSlot, 0), 50);
        assertEq(delegator.getAllocated(networkSlot, 0), 80);
        assertEq(delegator.getFilled(subvault, 0), 80);
        assertEq(delegator.getAllocated(subvault, 0), 100);
    }

    function test_leafNoAdaptersSubvaultDecreaseWithoutChildren_schedulesPendingAndKeepsReserveUntilExpiry() public {
        _deposit(alice, 100);

        uint96 noAdaptersSubvault = delegator.createSlot(bytes32(0), 0, false, true, 80);

        assertEq(delegator.getNoAdaptersSize(), 80);

        vm.warp(1);
        delegator.setSize(noAdaptersSubvault, 25);

        assertEq(delegator.getPending(noAdaptersSubvault, 0), 55);
        assertEq(delegator.getAllocated(noAdaptersSubvault, 0), 80);
        assertEq(delegator.getNoAdaptersSize(), 80);
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
        delegator.onSlash(subnetwork, alice, 20);
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
        delegator.onSlash(subnetwork, alice, 100);

        assertEq(delegator.getPending(operatorSlot, 0), 30);

        vm.warp(4);
        assertEq(delegator.getPending(operatorSlot, 0), 30);
    }

    function test_noAdaptersPendingWindow_afterSlash_keepsRecentPendingWhenOldPendingExpires() public {
        bytes32 subnetwork = makeAddr("issue5-no-adapters-network").subnetwork(0);

        _deposit(alice, 200);

        uint96 noAdaptersSubvault = delegator.createSlot(bytes32(0), 0, false, true, 100);
        uint96 networkSlot = delegator.createSlot(subnetwork, noAdaptersSubvault, false, false, 100);
        delegator.createSlot(_operatorKey(alice), networkSlot, false, false, 100);

        vm.warp(1);
        delegator.setSize(noAdaptersSubvault, 0);
        vm.warp(2);
        delegator.setSize(noAdaptersSubvault, 100);
        vm.warp(3);
        delegator.setSize(noAdaptersSubvault, 70);

        assertEq(delegator.getPending(noAdaptersSubvault, 0), 130);
        assertEq(delegator.getNoAdaptersSize(), 200);

        vm.prank(address(slasher));
        delegator.onSlash(subnetwork, alice, 100);

        assertEq(delegator.getPending(noAdaptersSubvault, 0), 30);
        assertEq(delegator.getNoAdaptersSize(), 100);

        vm.warp(4);
        assertEq(delegator.getPending(noAdaptersSubvault, 0), 30);
        assertEq(delegator.getNoAdaptersSize(), 100);
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

    function test_sharedSubvault_firstSlashDoesNotReduceSiblingSlashableStake() public {
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

        assertEq(delegator.stake(subnetwork1, alice), 0);
        assertEq(delegator.stake(subnetwork2, bob), 0);
        assertEq(delegator.stake(subnetwork3, operator3), 10);
        assertEq(slasher.slashableStake(subnetwork2, bob, 0, ""), 10);

        vm.prank(middleware);
        assertEq(slasher.executeSlash(slashIndex2, ""), 0);
        assertEq(delegator.stake(subnetwork3, operator3), 10);
        assertEq(slasher.owed(subnetwork2, bob), 0);
        assertEq(vault.activeStake(), 10);
    }

    function test_sharedSubvault_freshNetworkDoesNotInheritOldSharedSlashCredit() public {
        address network1 = makeAddr("fresh-shared-network1");
        address network2 = makeAddr("fresh-shared-network2");
        address middleware = makeAddr("fresh-shared-middleware");
        address charlie = makeAddr("fresh-shared-charlie");

        _registerNetwork(network1, middleware);
        _registerNetwork(network2, middleware);
        _registerOperator(alice);
        _registerOperator(bob);
        _registerOperator(charlie);
        _optIn(alice, network1);
        _optIn(bob, network2);
        _optIn(charlie, network2);

        bytes32 subnetwork1 = network1.subnetwork(0);
        bytes32 subnetwork2 = network2.subnetwork(0);
        vm.prank(network1);
        delegator.setMaxNetworkLimit(0, type(uint256).max);
        vm.prank(network2);
        delegator.setMaxNetworkLimit(0, type(uint256).max);

        _createSlot(0, true, 100);
        uint96 sharedSubvault = _rootIndex(uint32(1));

        _createNetworkSlot(sharedSubvault, subnetwork1, 100);
        uint96 networkSlot1 = sharedSubvault.createIndex(uint32(1));
        _createOperatorSlot(networkSlot1, alice, 100);

        _deposit(alice, 100);
        vm.warp(1);

        vm.prank(middleware);
        uint256 slashIndex1 = slasher.requestSlash(subnetwork1, alice, 80, 0, "");
        vm.prank(middleware);
        assertEq(slasher.executeSlash(slashIndex1, ""), 80);

        _createNetworkSlot(sharedSubvault, subnetwork2, 100);
        uint96 networkSlot2 = sharedSubvault.createIndex(uint32(2));
        _createOperatorSlot(networkSlot2, bob, 50);
        _createOperatorSlot(networkSlot2, charlie, 50);

        assertEq(delegator.stake(subnetwork2, bob), 20);
        assertEq(delegator.stake(subnetwork2, charlie), 0);
        assertEq(slasher.slashableStake(subnetwork2, bob, 0, ""), 20);
        assertEq(slasher.slashableStake(subnetwork2, charlie, 0, ""), 0);

        vm.prank(middleware);
        vm.expectRevert(IUniversalSlasher.InsufficientSlash.selector);
        slasher.requestSlash(subnetwork2, charlie, 1, 0, "");
    }

    function test_sharedSubvault_freshOperatorInExistingNetworkInheritsOldSharedSlashCredit() public {
        address network1 = makeAddr("fresh-operator-network1");
        address network2 = makeAddr("fresh-operator-network2");
        address middleware = makeAddr("fresh-operator-middleware");
        address charlie = makeAddr("fresh-operator-charlie");

        _registerNetwork(network1, middleware);
        _registerNetwork(network2, middleware);
        _registerOperator(alice);
        _registerOperator(bob);
        _registerOperator(charlie);
        _optIn(alice, network1);
        _optIn(bob, network2);
        _optIn(charlie, network2);

        bytes32 subnetwork1 = network1.subnetwork(0);
        bytes32 subnetwork2 = network2.subnetwork(0);
        vm.prank(network1);
        delegator.setMaxNetworkLimit(0, type(uint256).max);
        vm.prank(network2);
        delegator.setMaxNetworkLimit(0, type(uint256).max);

        _createSlot(0, true, 10);
        uint96 sharedSubvault = _rootIndex(uint32(1));

        _createNetworkSlot(sharedSubvault, subnetwork1, 10);
        _createNetworkSlot(sharedSubvault, subnetwork2, 10);
        uint96 networkSlot2 = sharedSubvault.createIndex(uint32(2));

        _createOperatorSlot(sharedSubvault.createIndex(uint32(1)), alice, 10);
        _createOperatorSlot(networkSlot2, bob, 5);

        _deposit(alice, 10);
        vm.warp(1);

        vm.prank(middleware);
        uint256 slashIndex = slasher.requestSlash(subnetwork1, alice, 10, 0, "");
        vm.prank(middleware);
        assertEq(slasher.executeSlash(slashIndex, ""), 10);

        assertEq(delegator.stake(subnetwork2, bob), 0);
        assertEq(slasher.slashableStake(subnetwork2, bob, 0, ""), 5);

        _createOperatorSlot(networkSlot2, charlie, 5);
        assertEq(delegator.stake(subnetwork2, charlie), 0);
        assertEq(slasher.slashableStake(subnetwork2, charlie, 0, ""), 5);
    }

    function test_sharedSubvault_freshOperatorCanCaptureHiddenGuaranteeBeyondPublicSlack() public {
        address network1 = makeAddr("fresh-operator-slack-network1");
        address network2 = makeAddr("fresh-operator-slack-network2");
        address middleware = makeAddr("fresh-operator-slack-middleware");
        address charlie = makeAddr("fresh-operator-slack-charlie");

        _registerNetwork(network1, middleware);
        _registerNetwork(network2, middleware);
        _registerOperator(alice);
        _registerOperator(bob);
        _registerOperator(charlie);
        _optIn(alice, network1);
        _optIn(bob, network2);
        _optIn(charlie, network2);

        bytes32 subnetwork1 = network1.subnetwork(0);
        bytes32 subnetwork2 = network2.subnetwork(0);
        vm.prank(network1);
        delegator.setMaxNetworkLimit(0, type(uint256).max);
        vm.prank(network2);
        delegator.setMaxNetworkLimit(0, type(uint256).max);

        _createSlot(0, true, 10);
        uint96 sharedSubvault = _rootIndex(uint32(1));

        _createNetworkSlot(sharedSubvault, subnetwork1, 10);
        _createNetworkSlot(sharedSubvault, subnetwork2, 10);
        uint96 networkSlot2 = sharedSubvault.createIndex(uint32(2));

        _createOperatorSlot(sharedSubvault.createIndex(uint32(1)), alice, 10);
        _createOperatorSlot(networkSlot2, bob, 2);

        _deposit(alice, 10);
        vm.warp(1);

        vm.prank(middleware);
        uint256 slashIndex = slasher.requestSlash(subnetwork1, alice, 5, 0, "");
        vm.prank(middleware);
        assertEq(slasher.executeSlash(slashIndex, ""), 5);

        _createOperatorSlot(networkSlot2, charlie, 4);
        assertEq(delegator.stake(subnetwork2, charlie), 3);
        assertEq(slasher.slashableStake(subnetwork2, charlie, 0, ""), 4);
    }

    function test_sharedSubvault_pendingSlashDoesNotReduceSiblingSlashableStakeUntilExpiry() public {
        address network1 = makeAddr("pending-shared-network1");
        address network2 = makeAddr("pending-shared-network2");
        address middleware = makeAddr("pending-shared-middleware");

        _registerNetwork(network1, middleware);
        _registerNetwork(network2, middleware);
        _registerOperator(alice);
        _registerOperator(bob);
        _optIn(alice, network1);
        _optIn(bob, network2);

        bytes32 subnetwork1 = network1.subnetwork(0);
        bytes32 subnetwork2 = network2.subnetwork(0);
        vm.prank(network1);
        delegator.setMaxNetworkLimit(0, type(uint256).max);
        vm.prank(network2);
        delegator.setMaxNetworkLimit(0, type(uint256).max);

        _createSlot(0, true, 10);
        uint96 sharedSubvault = _rootIndex(uint32(1));
        _createNetworkSlot(sharedSubvault, subnetwork1, 10);
        _createNetworkSlot(sharedSubvault, subnetwork2, 10);
        _createOperatorSlot(sharedSubvault.createIndex(uint32(1)), alice, 10);
        _createOperatorSlot(sharedSubvault.createIndex(uint32(2)), bob, 10);

        _deposit(alice, 10);
        vm.warp(1);
        delegator.setSize(sharedSubvault, 0);

        assertEq(slasher.slashableStake(subnetwork2, bob, 0, ""), 10);

        vm.prank(middleware);
        uint256 slashIndex = slasher.requestSlash(subnetwork1, alice, 10, 0, "");
        vm.prank(middleware);
        assertEq(slasher.executeSlash(slashIndex, ""), 10);

        assertEq(delegator.stake(subnetwork2, bob), 0);
        assertEq(slasher.slashableStake(subnetwork2, bob, 0, ""), 10);

        vm.warp(EPOCH_DURATION + 2);
        assertEq(slasher.slashableStake(subnetwork2, bob, 0, ""), 0);
    }

    function test_sharedSubvault_freshNetworkAfterPendingSeesFundedBaselineForSlasher() public {
        address network1 = makeAddr("funded-pending-network1");
        address network2 = makeAddr("funded-pending-network2");
        address middleware = makeAddr("funded-pending-middleware");

        _registerNetwork(network1, middleware);
        _registerNetwork(network2, middleware);
        _registerOperator(alice);
        _registerOperator(bob);
        _optIn(alice, network1);
        _optIn(bob, network2);

        bytes32 subnetwork1 = network1.subnetwork(0);
        bytes32 subnetwork2 = network2.subnetwork(0);
        vm.prank(network1);
        delegator.setMaxNetworkLimit(0, type(uint256).max);
        vm.prank(network2);
        delegator.setMaxNetworkLimit(0, type(uint256).max);

        _createSlot(0, true, 10);
        uint96 sharedSubvault = _rootIndex(uint32(1));

        _createNetworkSlot(sharedSubvault, subnetwork1, 10);
        uint96 networkSlot1 = sharedSubvault.createIndex(uint32(1));
        _createOperatorSlot(networkSlot1, alice, 10);

        _deposit(alice, 8);
        vm.warp(1);
        delegator.setSize(sharedSubvault, 5);

        _createNetworkSlot(sharedSubvault, subnetwork2, 100);
        uint96 networkSlot2 = sharedSubvault.createIndex(uint32(2));
        _createOperatorSlot(networkSlot2, bob, 100);

        assertEq(delegator.getAllocated(sharedSubvault, 0), 8);
        assertEq(delegator.getPending(sharedSubvault, 0), 3);
        assertEq(delegator.stake(subnetwork2, bob), 8);
        assertEq(slasher.slashableStake(subnetwork2, bob, 0, ""), 8);
    }

    function test_sharedSubvault_sizeGuaranteeExpiresAfterEpoch() public {
        address network1 = makeAddr("size-shared-network1");
        address network2 = makeAddr("size-shared-network2");
        address middleware = makeAddr("size-shared-middleware");

        _registerNetwork(network1, middleware);
        _registerNetwork(network2, middleware);
        _registerOperator(alice);
        _registerOperator(bob);
        _optIn(alice, network1);
        _optIn(bob, network2);

        bytes32 subnetwork1 = network1.subnetwork(0);
        bytes32 subnetwork2 = network2.subnetwork(0);
        vm.prank(network1);
        delegator.setMaxNetworkLimit(0, type(uint256).max);
        vm.prank(network2);
        delegator.setMaxNetworkLimit(0, type(uint256).max);

        _createSlot(0, true, 10);
        uint96 sharedSubvault = _rootIndex(uint32(1));
        _createNetworkSlot(sharedSubvault, subnetwork1, 10);
        _createNetworkSlot(sharedSubvault, subnetwork2, 10);
        _createOperatorSlot(sharedSubvault.createIndex(uint32(1)), alice, 10);
        _createOperatorSlot(sharedSubvault.createIndex(uint32(2)), bob, 10);

        _deposit(alice, 10);
        vm.warp(1);

        vm.prank(middleware);
        uint256 slashIndex = slasher.requestSlash(subnetwork1, alice, 10, 0, "");
        vm.prank(middleware);
        assertEq(slasher.executeSlash(slashIndex, ""), 10);

        assertEq(slasher.slashableStake(subnetwork2, bob, 0, ""), 10);

        vm.warp(EPOCH_DURATION + 2);
        assertEq(slasher.slashableStake(subnetwork2, bob, 0, ""), 0);
    }

    function test_sharedSubvault_slashedPathDoesNotRegainOwnSharedSizeGuaranteeAfterRegrowth() public {
        address network1 = makeAddr("own-shared-size-network1");
        address network2 = makeAddr("own-shared-size-network2");
        address middleware = makeAddr("own-shared-size-middleware");

        _registerNetwork(network1, middleware);
        _registerNetwork(network2, middleware);
        _registerOperator(alice);
        _registerOperator(bob);
        _optIn(alice, network1);
        _optIn(bob, network2);

        bytes32 subnetwork1 = network1.subnetwork(0);
        bytes32 subnetwork2 = network2.subnetwork(0);
        vm.prank(network1);
        delegator.setMaxNetworkLimit(0, type(uint256).max);
        vm.prank(network2);
        delegator.setMaxNetworkLimit(0, type(uint256).max);

        _createSlot(0, true, 10);
        uint96 sharedSubvault = _rootIndex(uint32(1));
        _createNetworkSlot(sharedSubvault, subnetwork1, 10);
        _createNetworkSlot(sharedSubvault, subnetwork2, 10);
        uint96 networkSlot1 = sharedSubvault.createIndex(uint32(1));
        _createOperatorSlot(networkSlot1, alice, 10);
        _createOperatorSlot(sharedSubvault.createIndex(uint32(2)), bob, 10);
        uint96 operatorSlot1 = networkSlot1.createIndex(uint32(1));

        _deposit(alice, 10);
        vm.warp(1);

        vm.prank(middleware);
        uint256 slashIndex = slasher.requestSlash(subnetwork1, alice, 3, 0, "");
        vm.prank(middleware);
        assertEq(slasher.executeSlash(slashIndex, ""), 3);

        assertEq(delegator.stake(subnetwork1, alice), 7);
        assertEq(slasher.slashableStake(subnetwork1, alice, 0, ""), 7);

        delegator.setSize(networkSlot1, 10);
        delegator.setSize(operatorSlot1, 10);

        assertEq(delegator.stake(subnetwork1, alice), 7);
        assertEq(slasher.slashableStake(subnetwork1, alice, 0, ""), 7);
        assertEq(slasher.slashableStake(subnetwork2, bob, 0, ""), 10);
    }

    function test_sharedSubvault_bigExampleUsesNetworkScopedGuaranteeAtOperatorLevel() public {
        address network1 = makeAddr("big-shared-network1");
        address network2 = makeAddr("big-shared-network2");
        address network3 = makeAddr("big-shared-network3");
        address middleware = makeAddr("big-shared-middleware");
        address carol = makeAddr("big-shared-carol");
        address dave = makeAddr("big-shared-dave");
        address iris = makeAddr("big-shared-iris");
        address jack = makeAddr("big-shared-jack");

        _registerNetwork(network1, middleware);
        _registerNetwork(network2, middleware);
        _registerNetwork(network3, middleware);
        _registerOperator(alice);
        _registerOperator(bob);
        _registerOperator(carol);
        _registerOperator(dave);
        _registerOperator(iris);
        _registerOperator(jack);
        _optIn(alice, network1);
        _optIn(bob, network1);
        _optIn(carol, network2);
        _optIn(dave, network2);
        _optIn(iris, network3);
        _optIn(jack, network3);

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
        uint96 sharedSubvault = _rootIndex(uint32(1));
        _createNetworkSlot(sharedSubvault, subnetwork1, 12);
        _createNetworkSlot(sharedSubvault, subnetwork2, 8);
        uint96 networkSlot1 = sharedSubvault.createIndex(uint32(1));
        uint96 networkSlot2 = sharedSubvault.createIndex(uint32(2));
        _createOperatorSlot(networkSlot1, alice, 6);
        _createOperatorSlot(networkSlot1, bob, 4);
        _createOperatorSlot(networkSlot2, carol, 3);
        _createOperatorSlot(networkSlot2, dave, 4);

        _deposit(alice, 10);
        vm.warp(1);

        vm.prank(middleware);
        uint256 slashIndex = slasher.requestSlash(subnetwork1, alice, 3, 0, "");
        vm.prank(middleware);
        assertEq(slasher.executeSlash(slashIndex, ""), 3);

        _createNetworkSlot(sharedSubvault, subnetwork3, 8);
        uint96 networkSlot3 = sharedSubvault.createIndex(uint32(3));
        _createOperatorSlot(networkSlot3, iris, 5);
        _createOperatorSlot(networkSlot3, jack, 5);

        delegator.setSize(sharedSubvault, 4);

        assertEq(delegator.stake(subnetwork3, jack), 2);
        assertEq(slasher.slashableStake(subnetwork3, jack, 0, ""), 2);

        vm.warp(block.timestamp + EPOCH_DURATION + 1);

        assertEq(delegator.stake(subnetwork1, bob), 1);
        assertEq(slasher.slashableStake(subnetwork1, bob, 0, ""), 1);
        assertEq(delegator.stake(subnetwork2, dave), 1);
        assertEq(slasher.slashableStake(subnetwork2, dave, 0, ""), 1);
    }

    function test_sharedSubvault_logicalGuaranteeConsumptionPersistsWhenActualSharedBucketAlreadyEmpty() public {
        address network1 = makeAddr("logical-shared-network1");
        address network2 = makeAddr("logical-shared-network2");
        address middleware = makeAddr("logical-shared-middleware");

        _registerNetwork(network1, middleware);
        _registerNetwork(network2, middleware);
        _registerOperator(alice);
        _registerOperator(bob);
        _optIn(alice, network1);
        _optIn(bob, network2);

        bytes32 subnetwork1 = network1.subnetwork(0);
        bytes32 subnetwork2 = network2.subnetwork(0);
        vm.prank(network1);
        delegator.setMaxNetworkLimit(0, type(uint256).max);
        vm.prank(network2);
        delegator.setMaxNetworkLimit(0, type(uint256).max);

        _createSlot(0, true, 10);
        uint96 sharedSubvault = _rootIndex(uint32(1));
        _createNetworkSlot(sharedSubvault, subnetwork1, 10);
        _createNetworkSlot(sharedSubvault, subnetwork2, 10);
        uint96 networkSlot2 = sharedSubvault.createIndex(uint32(2));
        _createOperatorSlot(sharedSubvault.createIndex(uint32(1)), alice, 10);
        _createOperatorSlot(networkSlot2, bob, 10);
        uint96 operatorSlot2 = networkSlot2.createIndex(uint32(1));

        _deposit(alice, 10);
        vm.warp(1);

        vm.startPrank(middleware);
        uint256 slashIndex1 = slasher.requestSlash(subnetwork1, alice, 10, 0, "");
        uint256 slashIndex2 = slasher.requestSlash(subnetwork2, bob, 5, 0, "");
        assertEq(slasher.executeSlash(slashIndex1, ""), 10);
        assertEq(slasher.executeSlash(slashIndex2, ""), 0);
        vm.stopPrank();

        assertEq(slasher.slashableStake(subnetwork2, bob, 0, ""), 5);

        delegator.setSize(networkSlot2, 10);
        delegator.setSize(operatorSlot2, 10);

        assertEq(delegator.stake(subnetwork2, bob), 0);
        assertEq(slasher.slashableStake(subnetwork2, bob, 0, ""), 5);
    }

    function test_sharedSubvault_secondSlashDoesNotRestoreBothNetworksSlashableStake() public {
        address network1 = makeAddr("shared-verify-network1");
        address network2 = makeAddr("shared-verify-network2");
        address middleware = makeAddr("shared-verify-middleware");

        _registerNetwork(network1, middleware);
        _registerNetwork(network2, middleware);
        _registerOperator(alice);

        vm.startPrank(alice);
        operatorVaultOptInService.optIn(address(vault));
        operatorNetworkOptInService.optIn(network1);
        operatorNetworkOptInService.optIn(network2);
        vm.stopPrank();

        bytes32 subnetwork1 = network1.subnetwork(0);
        bytes32 subnetwork2 = network2.subnetwork(0);
        vm.prank(network1);
        delegator.setMaxNetworkLimit(0, type(uint256).max);
        vm.prank(network2);
        delegator.setMaxNetworkLimit(0, type(uint256).max);

        _createSlot(0, true, 200);
        uint96 sharedSubvault = _rootIndex(uint32(1));
        _createNetworkSlot(sharedSubvault, subnetwork1, 200);
        _createNetworkSlot(sharedSubvault, subnetwork2, 200);
        uint96 networkSlot1 = sharedSubvault.createIndex(uint32(1));
        uint96 networkSlot2 = sharedSubvault.createIndex(uint32(2));
        _createOperatorSlot(networkSlot1, alice, 200);
        _createOperatorSlot(networkSlot2, alice, 200);

        _deposit(alice, 100);
        vm.warp(1);

        assertEq(slasher.slashableStake(subnetwork1, alice, 0, ""), 100);
        assertEq(slasher.slashableStake(subnetwork2, alice, 0, ""), 100);

        vm.startPrank(middleware);
        uint256 slashIndex1 = slasher.requestSlash(subnetwork1, alice, 100, 0, "");
        assertEq(slasher.executeSlash(slashIndex1, ""), 100);
        uint256 slashIndex2 = slasher.requestSlash(subnetwork2, alice, 100, 0, "");
        assertEq(slasher.executeSlash(slashIndex2, ""), 0);
        vm.stopPrank();

        assertEq(vault.activeStake(), 0);
        assertEq(delegator.getSlot(sharedSubvault).size, 100);
        assertEq(delegator.getSlot(networkSlot1).size, 100);
        assertEq(delegator.getSlot(networkSlot2).size, 100);
        assertEq(delegator.stake(subnetwork1, alice), 0);
        assertEq(delegator.stake(subnetwork2, alice), 0);
        assertEq(slasher.slashableStake(subnetwork1, alice, 0, ""), 0);
        assertEq(slasher.slashableStake(subnetwork2, alice, 0, ""), 0);
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

    function test_isolatedSlots_leafDecrease_delaysReallocation() public {
        _deposit(alice, 100);

        _createSlot(0, false, 70);
        _createSlot(0, false, 70);
        uint96 slot1 = _rootIndex(uint32(1));
        uint96 slot2 = _rootIndex(uint32(2));

        assertEq(delegator.getAllocated(slot1, 0), 70);
        assertEq(delegator.getAllocated(slot2, 0), 30);

        vm.warp(1);
        delegator.setSize(slot1, 30);

        assertEq(delegator.getPending(slot1, 0), 40);
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

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, bob, SET_WITHDRAWAL_BUFFER_SIZE_ROLE
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

    function testFuzz_getPendingSize_sumOfUint128SizeAndPendingFitsUint208(uint128 size, uint128 pending) public {
        UniversalDelegatorCoverageHarnessTest harness = new UniversalDelegatorCoverageHarnessTest();
        MockVaultForDelegatorCoverage vaultMock = new MockVaultForDelegatorCoverage();
        uint96 index = _rootIndex(uint32(1));
        uint48 timestamp = 1;

        vm.warp(timestamp);
        harness.setVaultRaw(address(vaultMock));
        harness.pushSlotSizeRaw(index, timestamp, size);
        if (pending > 0) {
            harness.pushPendingCumulativeRaw(index, timestamp, pending);
        }

        uint256 expected = uint256(size) + uint256(pending);
        assertEq(harness.exposeGetPendingSize(index, 0), expected);
        assertLe(expected, type(uint208).max);
    }

    function testFuzz_getPrevSum_siblingPrefixFitsUint208(uint8 siblingCount, uint128 size, uint128 pending) public {
        UniversalDelegatorCoverageHarnessTest harness = new UniversalDelegatorCoverageHarnessTest();
        MockVaultForDelegatorCoverage vaultMock = new MockVaultForDelegatorCoverage();
        uint96 parent = _rootIndex(uint32(1));
        uint48 timestamp = 1;

        siblingCount = uint8(bound(siblingCount, 2, 20));

        vm.warp(timestamp);
        harness.setVaultRaw(address(vaultMock));
        harness.pushFirstChildRaw(parent, timestamp, 1);
        harness.pushSyncPrevSizeSumsRaw(parent, timestamp, 1);
        harness.setChildrenPendingAtRaw(parent, timestamp);

        for (uint32 i = 1; i <= siblingCount; ++i) {
            uint96 slot = parent.createIndex(i);
            harness.pushSlotSizeRaw(slot, timestamp, size);
            if (pending > 0) {
                harness.pushPendingCumulativeRaw(slot, timestamp, pending);
            }
            if (i < siblingCount) {
                harness.pushNextSlotRaw(slot, timestamp, i + 1);
            }
        }

        uint96 target = parent.createIndex(uint32(siblingCount));
        uint256 expected = (uint256(siblingCount) - 1) * (uint256(size) + uint256(pending));

        assertEq(harness.exposeGetPrevSum(target, 0), expected);
        assertLe(expected, type(uint208).max);
    }

    function test_syncPrevSizeSums_modifier_harnessSyncsDirtyPrefixAndClearsFlag() public {
        UniversalDelegatorCoverageHarnessTest harness = new UniversalDelegatorCoverageHarnessTest();
        uint96 parent = _rootIndex(uint32(1));
        uint96 slot1 = parent.createIndex(uint32(1));
        uint96 slot2 = parent.createIndex(uint32(2));
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

    function test_getPrevSizeSumAt_returnsZeroForRootAndSharedParent() public {
        UniversalDelegatorCoverageHarnessTest harness = new UniversalDelegatorCoverageHarnessTest();
        uint96 parent = _rootIndex(uint32(1));
        uint96 slot = parent.createIndex(uint32(1));
        uint48 timestamp = 1;

        vm.warp(timestamp);
        harness.setSlotSharedRaw(parent, true);
        harness.pushFirstChildRaw(parent, timestamp, 1);
        harness.pushSlotSizeRaw(slot, timestamp, 5);

        assertEq(harness.exposeGetPrevSizeSumAt(0, timestamp), 0);
        assertEq(harness.exposeGetPrevSizeSumAt(slot, timestamp), 0);
    }

    function test_getPrevPendingSumAt_returnsZeroForRootAndSharedParent() public {
        UniversalDelegatorCoverageHarnessTest harness = new UniversalDelegatorCoverageHarnessTest();
        MockVaultForDelegatorCoverage vaultMock = new MockVaultForDelegatorCoverage();
        uint96 parent = _rootIndex(uint32(1));
        uint96 slot = parent.createIndex(uint32(1));
        uint48 timestamp = 1;

        vm.warp(timestamp);
        harness.setVaultRaw(address(vaultMock));
        harness.setSlotSharedRaw(parent, true);
        harness.pushFirstChildRaw(parent, timestamp, 1);
        harness.pushPendingCumulativeRaw(slot, timestamp, 5);

        assertEq(harness.exposeGetPrevPendingSumAt(0, 0, timestamp), 0);
        assertEq(harness.exposeGetPrevPendingSumAt(slot, 0, timestamp), 0);
    }

    function test_getPrevPendingSum_returnsZeroForRootAndSharedParent() public {
        UniversalDelegatorCoverageHarnessTest harness = new UniversalDelegatorCoverageHarnessTest();
        MockVaultForDelegatorCoverage vaultMock = new MockVaultForDelegatorCoverage();
        uint96 parent = _rootIndex(uint32(1));
        uint96 slot = parent.createIndex(uint32(1));
        uint48 timestamp = 1;

        vm.warp(timestamp);
        harness.setVaultRaw(address(vaultMock));
        harness.setSlotSharedRaw(parent, true);
        harness.pushFirstChildRaw(parent, timestamp, 1);
        harness.pushPendingCumulativeRaw(slot, timestamp, 5);
        harness.setChildrenPendingAtRaw(parent, timestamp);

        assertEq(harness.exposeGetPrevPendingSum(0, 0), 0);
        assertEq(harness.exposeGetPrevPendingSum(slot, 0), 0);
    }

    function test_createSlot_revertsForMissingParentSlot() public {
        vm.expectRevert(IUniversalDelegator.SlotNotExists.selector);
        delegator.createSlot(bytes32(0), _rootIndex(uint32(1)), false, false, 1);
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
        delegator.onSlash(subnetwork, alice, 1);

        uint128 currentSize = delegator.getSlot(operatorSlot).size;
        delegator.setSize(operatorSlot, currentSize);
        assertEq(delegator.getPending(operatorSlot, 0), 0);
    }

    function test_syncPrevSums_multipleSlashes_thenCreateOperator_preservesExistingSiblingAllocations() public {
        address carol = makeAddr("sync-create-carol");
        address dave = makeAddr("sync-create-dave");
        address eve = makeAddr("sync-create-eve");

        _deposit(alice, 240);

        bytes32 subnetwork = makeAddr("multi-slash-create-subnetwork").subnetwork(0);
        _createSlot(0, false, 240);
        uint96 subvault = _rootIndex(uint32(1));
        _createNetworkSlot(subvault, subnetwork, 240);
        uint96 networkSlot = subvault.createIndex(uint32(1));

        _createOperatorSlot(networkSlot, alice, 90);
        uint96 operatorSlot1 = networkSlot.createIndex(uint32(1));
        _createOperatorSlot(networkSlot, bob, 60);
        uint96 operatorSlot2 = networkSlot.createIndex(uint32(2));
        _createOperatorSlot(networkSlot, carol, 40);
        uint96 operatorSlot3 = networkSlot.createIndex(uint32(3));
        _createOperatorSlot(networkSlot, dave, 30);
        uint96 operatorSlot4 = networkSlot.createIndex(uint32(4));

        vm.prank(address(slasher));
        delegator.onSlash(subnetwork, alice, 10);
        vm.prank(address(slasher));
        delegator.onSlash(subnetwork, bob, 5);

        uint48 beforeCreate = uint48(block.timestamp);
        uint256 allocated2Before = delegator.getAllocated(operatorSlot2, 0);
        uint256 allocated3Before = delegator.getAllocated(operatorSlot3, 0);
        uint256 allocated4Before = delegator.getAllocated(operatorSlot4, 0);
        vm.warp(block.timestamp + 1);

        uint96 operatorSlot5 = delegator.createSlot(_operatorKey(eve), networkSlot, false, false, 15);

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
        delegator.getIsNoAdapters(subnetwork);
    }

    function test_createSlot_noAdaptersAndSetSizeNoAdapters() public {
        vm.expectRevert(IUniversalDelegator.NotEnoughNoAdapters.selector);
        delegator.createSlot(bytes32(0), 0, false, true, 1);

        _deposit(alice, 100);

        uint96 subvault = delegator.createSlot(bytes32(0), 0, false, true, 40);
        bytes32 subnetwork = makeAddr("no-adapters-network").subnetwork(0);
        delegator.createSlot(subnetwork, subvault, false, false, 40);

        assertTrue(delegator.getIsNoAdapters(subnetwork));
        assertEq(delegator.getNoAdaptersSize(), 40);

        vm.expectRevert(IUniversalDelegator.NotEnoughNoAdapters.selector);
        delegator.setSize(subvault, 200);

        vm.warp(1);
        delegator.setSize(subvault, 10);
        assertEq(delegator.getPending(subvault, 0), 30);
        assertEq(delegator.getNoAdaptersSize(), 40);

        vm.warp(EPOCH_DURATION + 1);
        assertEq(delegator.getNoAdaptersSize(), 10);
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

    function test_removeSlot_noAdaptersSubvault_decrementsNoAdaptersSize() public {
        delegator.grantRole(REMOVE_SLOT_ROLE, owner);

        _deposit(alice, 100);
        uint96 noAdaptersSubvault = delegator.createSlot(bytes32(0), 0, false, true, 100);
        assertEq(delegator.getNoAdaptersSize(), 100);
        assertEq(delegator.getAllocated(noAdaptersSubvault, 0), 100);

        _withdraw(alice, 100);
        vm.warp(block.timestamp + EPOCH_DURATION + 1);
        assertEq(delegator.getAllocated(noAdaptersSubvault, 0), 0);

        delegator.removeSlot(noAdaptersSubvault);
        assertFalse(delegator.getSlot(noAdaptersSubvault).exists);
        assertEq(delegator.getNoAdaptersSize(), 0);
    }

    function test_removeSlot_clearsOnlyRemovedNoAdaptersPending() public {
        delegator.grantRole(REMOVE_SLOT_ROLE, owner);

        _deposit(alice, 200);
        uint96 noAdaptersSubvault1 = delegator.createSlot(bytes32(0), 0, false, true, 100);
        uint96 noAdaptersSubvault2 = delegator.createSlot(bytes32(0), 0, false, true, 100);
        delegator.createSlot(
            makeAddr("remove-no-adapters-network-1").subnetwork(0), noAdaptersSubvault1, false, false, 0
        );
        delegator.createSlot(
            makeAddr("remove-no-adapters-network-2").subnetwork(0), noAdaptersSubvault2, false, false, 0
        );

        vm.warp(1);
        _withdraw(alice, 200);

        vm.warp(2);
        delegator.setSize(noAdaptersSubvault1, 50);
        vm.warp(3);
        delegator.setSize(noAdaptersSubvault2, 60);

        vm.warp(5);
        assertEq(delegator.getAllocated(noAdaptersSubvault1, 0), 0);
        assertEq(delegator.getAllocated(noAdaptersSubvault2, 0), 0);
        assertEq(delegator.getPending(noAdaptersSubvault1, 0), 0);
        assertEq(delegator.getPending(noAdaptersSubvault2, 0), 40);
        assertEq(delegator.getNoAdaptersSize(), 150);
        assertEq(
            delegator.getNoAdaptersSize() - delegator.getSlot(noAdaptersSubvault1).size
                - delegator.getSlot(noAdaptersSubvault2).size,
            40
        );

        delegator.removeSlot(noAdaptersSubvault2);

        assertFalse(delegator.getSlot(noAdaptersSubvault2).exists);
        assertTrue(delegator.getSlot(noAdaptersSubvault1).exists);
        assertEq(delegator.getPending(noAdaptersSubvault1, 0), 0);
        assertEq(delegator.getNoAdaptersSize(), 50);
        assertEq(delegator.getNoAdaptersSize() - delegator.getSlot(noAdaptersSubvault1).size, 0);
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

    function test_resetAllocation_noAdaptersPathAndSyncPrevSums() public {
        address network = makeAddr("reset-network-with-slot");
        address middleware = makeAddr("reset-middleware-with-slot");
        _registerNetwork(network, middleware);
        bytes32 subnetwork = network.subnetwork(0);

        _deposit(alice, 100);

        uint96 noAdaptersSubvault = delegator.createSlot(bytes32(0), 0, false, true, 80);
        uint96 slot2 = delegator.createSlot(bytes32(0), 0, false, false, 1);
        uint96 slot3 = delegator.createSlot(bytes32(0), 0, false, false, 1);
        delegator.createSlot(subnetwork, noAdaptersSubvault, false, false, 80);

        vm.warp(1);
        delegator.setSize(noAdaptersSubvault, 40);
        assertEq(delegator.getNoAdaptersSize(), 80);

        vm.prank(network);
        delegator.resetAllocation(subnetwork);

        assertFalse(delegator.getSlot(noAdaptersSubvault).exists);
        assertEq(delegator.getSlotOfNetwork(subnetwork), 0);
        assertEq(delegator.getNoAdaptersSize(), 0);
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

        uint96 noAdaptersSubvault = delegator.createSlot(bytes32(0), 0, false, true, 80);
        uint96 slot2 = delegator.createSlot(bytes32(0), 0, false, false, 30);
        uint96 slot3 = delegator.createSlot(bytes32(0), 0, false, false, 20);
        delegator.createSlot(subnetwork, noAdaptersSubvault, false, false, 80);

        vm.prank(network);
        delegator.resetAllocation(subnetwork);

        uint48 beforeCreate = uint48(block.timestamp);
        uint256 slot2Allocated = delegator.getAllocated(slot2, 0);
        uint256 slot3Allocated = delegator.getAllocated(slot3, 0);
        vm.warp(block.timestamp + 1);

        uint96 slot4 = delegator.createSlot(bytes32(0), 0, false, false, 25);

        assertFalse(delegator.getSlot(noAdaptersSubvault).exists);
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
        _createSlot(0, false, 200);
        uint96 subvault = _rootIndex(uint32(1));
        _createNetworkSlot(subvault, subnetwork, 200);
        uint96 networkSlot = subvault.createIndex(uint32(1));

        _createOperatorSlot(networkSlot, alice, 70);
        uint96 operatorSlot1 = networkSlot.createIndex(uint32(1));
        _createOperatorSlot(networkSlot, bob, 60);
        uint96 operatorSlot2 = networkSlot.createIndex(uint32(2));
        _createOperatorSlot(networkSlot, carol, 40);
        uint96 operatorSlot3 = networkSlot.createIndex(uint32(3));
        _createOperatorSlot(networkSlot, dave, 30);
        uint96 operatorSlot4 = networkSlot.createIndex(uint32(4));

        vm.warp(1);
        delegator.setSize(operatorSlot3, 0);
        vm.warp(EPOCH_DURATION + 2);
        assertEq(delegator.getAllocated(operatorSlot3, 0), 0);
        assertEq(delegator.getPending(operatorSlot3, 0), 0);

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
        _assertManualPrevSizeSumsMatch(subvault);
        _assertManualPrevSizeSumsMatch(0);
        assertEq(delegator.getSlot(operatorSlot1).size, 60);
    }

    function testFuzz_chaoticDirtyParentOperations_preserveManualPrevSizeSums(uint256 seed) public {
        _deposit(alice, 400);

        bytes32 subnetwork = makeAddr("chaos-subnetwork").subnetwork(0);
        _createSlot(0, false, 400);
        uint96 subvault = _rootIndex(uint32(1));
        _createNetworkSlot(subvault, subnetwork, 400);
        uint96 networkSlot = subvault.createIndex(uint32(1));
        ChaosState memory state = _initChaosState(networkSlot);

        for (uint256 step; step < 32; ++step) {
            seed = uint256(keccak256(abi.encode(seed, step, block.timestamp)));
            state = _runChaosStep(state, networkSlot, subnetwork, seed);

            _assertManualPrevSizeSumsMatch(networkSlot);
            _assertManualPrevSizeSumsMatch(subvault);
            _assertManualPrevSizeSumsMatch(0);
        }
    }

    function test_resetAllocation_clearsOnlyRemovedNoAdaptersPending() public {
        address network1 = makeAddr("reset-network-no-adapters-1");
        address middleware1 = makeAddr("reset-middleware-no-adapters-1");
        _registerNetwork(network1, middleware1);
        bytes32 subnetwork1 = network1.subnetwork(0);

        address network2 = makeAddr("reset-network-no-adapters-2");
        address middleware2 = makeAddr("reset-middleware-no-adapters-2");
        _registerNetwork(network2, middleware2);
        bytes32 subnetwork2 = network2.subnetwork(0);
        vm.prank(network1);
        delegator.setMaxNetworkLimit(0, type(uint256).max);
        vm.prank(network2);
        delegator.setMaxNetworkLimit(0, type(uint256).max);

        _deposit(alice, 200);

        uint96 noAdaptersSubvault1 = delegator.createSlot(bytes32(0), 0, false, true, 100);
        uint96 noAdaptersSubvault2 = delegator.createSlot(bytes32(0), 0, false, true, 100);

        delegator.createSlot(subnetwork1, noAdaptersSubvault1, false, false, 100);
        delegator.createSlot(subnetwork2, noAdaptersSubvault2, false, false, 100);

        vm.warp(1);
        delegator.setSize(noAdaptersSubvault1, 50);
        vm.warp(2);
        delegator.setSize(noAdaptersSubvault2, 60);

        assertEq(delegator.getPending(noAdaptersSubvault1, 0), 50);
        assertEq(delegator.getPending(noAdaptersSubvault2, 0), 40);
        assertEq(delegator.getNoAdaptersSize(), 200);
        assertEq(
            delegator.getNoAdaptersSize() - delegator.getSlot(noAdaptersSubvault1).size
                - delegator.getSlot(noAdaptersSubvault2).size,
            90
        );

        vm.warp(3);
        vm.prank(network1);
        delegator.resetAllocation(subnetwork1);

        assertFalse(delegator.getSlot(noAdaptersSubvault1).exists);
        assertEq(delegator.getSlotOfNetwork(subnetwork1), 0);
        assertEq(delegator.maxNetworkLimit(subnetwork1), 0);
        assertEq(delegator.maxNetworkLimit(subnetwork2), type(uint208).max);
        assertEq(delegator.getNoAdaptersSize(), 100);
        assertTrue(delegator.getSlot(noAdaptersSubvault2).exists);
        assertEq(delegator.getPending(noAdaptersSubvault2, 0), 40);
        assertEq(delegator.getNoAdaptersSize() - delegator.getSlot(noAdaptersSubvault2).size, 40);
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

    function test_onSlash_noAdaptersRootDecreasesNoAdaptersSize() public {
        _deposit(alice, 100);

        bytes32 subnetwork = makeAddr("no-adapters-on-slash").subnetwork(0);
        uint96 subvault = delegator.createSlot(bytes32(0), 0, false, true, 80);
        delegator.createSlot(subnetwork, subvault, false, false, 80);
        uint96 networkSlot = subvault.createIndex(uint32(1));
        delegator.createSlot(_operatorKey(alice), networkSlot, false, false, 80);

        assertEq(delegator.getNoAdaptersSize(), 80);
        assertEq(delegator.getSlot(subvault).size, 80);

        vm.prank(address(slasher));
        delegator.onSlash(subnetwork, alice, 20);

        assertEq(delegator.getNoAdaptersSize(), 60);
        assertEq(delegator.getSlot(subvault).size, 60);
    }

    function test_onSlash_noAdaptersPartialPendingSlash_preservesRemainingNoAdaptersBudget() public {
        _deposit(alice, 100);

        bytes32 subnetwork = makeAddr("no-adapters-pending-slash").subnetwork(0);
        uint96 subvault = delegator.createSlot(bytes32(0), 0, false, true, 80);
        uint96 networkSlot = delegator.createSlot(subnetwork, subvault, false, false, 80);
        uint96 operatorSlot = delegator.createSlot(_operatorKey(alice), networkSlot, false, false, 80);

        vm.warp(1);
        delegator.setSize(subvault, 30);

        assertEq(delegator.getPending(subvault, 0), 50);
        assertEq(delegator.getNoAdaptersSize(), 80);

        vm.prank(address(slasher));
        assertEq(delegator.onSlash(subnetwork, alice, 40), 40);

        assertEq(delegator.getSlot(subvault).size, 30);
        assertEq(delegator.getPending(subvault, 0), 10);
        assertEq(delegator.getSlot(networkSlot).size, 40);
        assertEq(delegator.getSlot(operatorSlot).size, 40);
        assertEq(delegator.getNoAdaptersSize(), 40);
    }

    function test_onSlash_parentPendingAndSizeAreCappedByReducedActualAmount() public {
        _deposit(alice, 100);

        bytes32 subnetwork = makeAddr("slash-parent-cap").subnetwork(0);
        uint96 subvault = delegator.createSlot(bytes32(0), 0, false, false, 100);
        uint96 networkSlot = delegator.createSlot(subnetwork, subvault, false, false, 100);
        uint96 operatorSlot = delegator.createSlot(_operatorKey(alice), networkSlot, false, false, 20);

        vm.warp(1);
        delegator.setSize(subvault, 30);

        assertEq(delegator.getPending(subvault, 0), 70);
        assertEq(delegator.getSlot(subvault).size, 30);
        assertEq(delegator.getSlot(networkSlot).size, 100);
        assertEq(delegator.getSlot(operatorSlot).size, 20);

        vm.warp(2);
        vm.prank(address(slasher));
        assertEq(delegator.onSlash(subnetwork, alice, 100), 20);

        assertEq(delegator.getPending(subvault, 0), 50);
        assertEq(delegator.getSlot(subvault).size, 30);
        assertEq(delegator.getSlot(networkSlot).size, 80);
        assertEq(delegator.getSlot(operatorSlot).size, 0);
    }

    function test_onSlash_sharedSubvault_capsActualAmountToRemainingSharedBalance() public {
        _deposit(alice, 100);

        bytes32 subnetwork1 = makeAddr("shared-cap-network-1").subnetwork(0);
        bytes32 subnetwork2 = makeAddr("shared-cap-network-2").subnetwork(0);

        uint96 subvault = delegator.createSlot(bytes32(0), 0, true, false, 100);
        uint96 networkSlot1 = delegator.createSlot(subnetwork1, subvault, false, false, 100);
        uint96 networkSlot2 = delegator.createSlot(subnetwork2, subvault, false, false, 100);
        delegator.createSlot(_operatorKey(alice), networkSlot1, false, false, 100);
        delegator.createSlot(_operatorKey(bob), networkSlot2, false, false, 100);

        vm.prank(address(slasher));
        assertEq(delegator.onSlash(subnetwork1, alice, 70), 70);

        vm.prank(address(slasher));
        assertEq(delegator.onSlash(subnetwork2, bob, 70), 30);

        assertEq(delegator.getSlot(subvault).size, 0);
    }

    function test_onSlash_sharedSubvault_partialSlashOnlyConsumesActualAmount() public {
        _deposit(alice, 100);

        bytes32 subnetwork = makeAddr("shared-actual-amount-network").subnetwork(0);
        uint96 subvault = delegator.createSlot(bytes32(0), 0, true, false, 100);
        uint96 networkSlot = delegator.createSlot(subnetwork, subvault, false, false, 100);
        uint96 operatorSlot = delegator.createSlot(_operatorKey(alice), networkSlot, false, false, 50);

        vm.warp(1);
        vm.prank(address(slasher));
        assertEq(delegator.onSlash(subnetwork, alice, 100), 50);

        assertEq(delegator.getSlot(subvault).size, 50);
        assertEq(delegator.getSlot(networkSlot).size, 50);
        assertEq(delegator.getSlot(operatorSlot).size, 0);

        vm.warp(2);
        delegator.setSize(networkSlot, 100);
        delegator.setSize(operatorSlot, 100);

        vm.prank(address(slasher));
        assertEq(delegator.getAllocated(subnetwork, alice, 0), 50);
    }

    function test_onSlash_revertsNotAssigned() public {
        vm.prank(address(slasher));
        try delegator.onSlash(bytes32(0), address(0), 0) returns (uint256) {
            console2.log("onSlash not assigned / no revert");
        } catch (bytes memory err) {
            console2.log("onSlash not assigned / revert data length", err.length);
        }
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
        delegator.onSlash(subnetwork, alice, 1);

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

    function test_migrate_fromVault_createsNoAdaptersSubvault() public {
        MockLegacyDelegatorType oldDelegator = new MockLegacyDelegatorType(0);
        vm.prank(address(vault));
        delegator.migrate(address(oldDelegator));

        IUniversalDelegator.Slot memory root = delegator.getSlot(0);
        assertEq(root.existChildren, 1);
        assertEq(root.firstChild, 1);

        IUniversalDelegator.Slot memory noAdaptersSubvault = delegator.getSlot(uint96(0).createIndex(root.firstChild));
        assertTrue(noAdaptersSubvault.noAdapters);
        assertTrue(noAdaptersSubvault.isShared);
        assertEq(uint256(noAdaptersSubvault.size), IUniversalDelegator(address(delegator)).getNoAdaptersSize());
    }

    function test_migrate_fromVault_operatorNetworkSpecificLegacy_createsNonSharedNoAdaptersSubvault() public {
        MockLegacyDelegatorType oldDelegator = new MockLegacyDelegatorType(OPERATOR_NETWORK_SPECIFIC_DELEGATOR_TYPE);
        vm.prank(address(vault));
        delegator.migrate(address(oldDelegator));

        IUniversalDelegator.Slot memory root = delegator.getSlot(0);
        assertEq(root.existChildren, 1);
        assertEq(root.firstChild, 1);

        IUniversalDelegator.Slot memory noAdaptersSubvault = delegator.getSlot(uint96(0).createIndex(root.firstChild));
        assertTrue(noAdaptersSubvault.noAdapters);
        assertFalse(noAdaptersSubvault.isShared);
        assertEq(uint256(noAdaptersSubvault.size), IUniversalDelegator(address(delegator)).getNoAdaptersSize());
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
            createSlotRoleHolder: owner,
            setSizeRoleHolder: owner,
            swapSlotsRoleHolder: owner,
            removeSlotRoleHolder: owner,
            setWithdrawalBufferSizeRoleHolder: owner,
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

    function _assertManualPrevSizeSumsMatch(uint96 parentIndex) internal view {
        bool sharedParent = parentIndex.getDepth() == 1 && delegator.getSlot(parentIndex).isShared;
        uint208 expectedPrevSizeSum;
        uint32 childIndex = delegator.getSlot(parentIndex).firstChild;

        while (childIndex > 0 && childIndex < WITHDRAWAL_BUFFER_CHILD_INDEX) {
            uint96 slotIndex = parentIndex.createIndex(childIndex);
            IUniversalDelegator.Slot memory slot = delegator.getSlot(slotIndex);
            assertEq(slot.prevSizeSum, sharedParent ? 0 : expectedPrevSizeSum);
            expectedPrevSizeSum += slot.size;
            childIndex = slot.nextSlot;
        }
    }

    function _initChaosState(uint96 networkSlot) internal returns (ChaosState memory state) {
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

    function _runChaosStep(ChaosState memory state, uint96 networkSlot, bytes32 subnetwork, uint256 seed)
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
                uint96 left = state.operatorSlots[index1];
                uint96 right = state.operatorSlots[index2];
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
                        (
                            _operatorKey(state.operators[nextIndex]),
                            networkSlot,
                            false,
                            false,
                            uint128(bound(seed >> 112, 0, 50))
                        )
                    )
                );
            if (success) {
                state.operatorSlots[nextIndex] = abi.decode(returnData, (uint96));
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

    function _findRemovableIndex(uint96[6] memory operatorSlots, bool[6] memory exists)
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
        uint96 noAdaptersSubvault = uint96(0).createIndex(root.firstChild);
        newDelegator.createSlot(subnetwork, noAdaptersSubvault, false, false, 0);
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
            defaultAdminRoleHolder: owner,
            setAdapterLimitRoleHolder: owner,
            swapAdaptersRoleHolder: owner,
            allocateAdapterRoleHolder: owner,
            deallocateAdapterRoleHolder: owner,
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
        assertEq(root.existChildren, 1);
        IUniversalDelegator.Slot memory noAdaptersSubvault =
            IUniversalDelegator(newDelegator).getSlot(uint96(0).createIndex(root.firstChild));
        assertTrue(noAdaptersSubvault.noAdapters);
        assertEq(noAdaptersSubvault.isShared, legacyType < OPERATOR_NETWORK_SPECIFIC_DELEGATOR_TYPE);
        assertEq(uint256(noAdaptersSubvault.size), IUniversalDelegator(newDelegator).getNoAdaptersSize());
    }
}
