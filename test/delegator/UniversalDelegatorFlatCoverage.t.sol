// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";

import {DelegatorFactory} from "../../src/contracts/DelegatorFactory.sol";
import {UniversalDelegator} from "../../src/contracts/delegator/UniversalDelegator.sol";
import {FenwickTreeCheckpoints} from "../../src/contracts/libraries/FenwickTreeCheckpoints.sol";
import {Subnetwork} from "../../src/contracts/libraries/Subnetwork.sol";
import {
    CREATE_SLOT_ROLE,
    REMOVE_SLOT_ROLE,
    SET_SIZE_ROLE,
    SWAP_SLOTS_ROLE
} from "../../src/interfaces/delegator/IUniversalDelegator.sol";
import {IUniversalDelegator} from "../../src/interfaces/delegator/IUniversalDelegator.sol";

contract UniversalDelegatorFlatRegistryMock {
    function isEntity(address) external pure returns (bool) {
        return true;
    }
}

contract UniversalDelegatorFlatConfigurableRegistryMock {
    mapping(address entity => bool status) public isEntity;

    function setEntity(address entity, bool status) external {
        isEntity[entity] = status;
    }
}

contract UniversalDelegatorFlatMiddlewareMock {
    mapping(address network => address middleware) public middleware;

    function setMiddleware(address network, address middleware_) external {
        middleware[network] = middleware_;
    }
}

contract UniversalDelegatorFlatVaultMock {
    uint48 public epochDuration = 10;
    uint64 public version = 2;
    uint256 public activeStake;
    address public slasher;

    function setVersion(uint64 version_) external {
        version = version_;
    }

    function setActiveStake(uint256 activeStake_) external {
        activeStake = activeStake_;
    }

    function setSlasher(address slasher_) external {
        slasher = slasher_;
    }

    function activeStakeAt(uint48, bytes calldata) external view returns (uint256) {
        return activeStake;
    }

    function activeWithdrawalsFor(uint48) external pure returns (uint256) {
        return 0;
    }

    function activeWithdrawalsForAt(uint48, uint48) external pure returns (uint256) {
        return 0;
    }
}

contract UniversalDelegatorFlatLegacyMock {
    uint256 public stakeAtValue;

    function setStakeAtValue(uint256 value) external {
        stakeAtValue = value;
    }

    function stakeAt(bytes32, address, uint48, bytes calldata) external view returns (uint256) {
        return stakeAtValue;
    }
}

contract UniversalDelegatorFlatHarness is UniversalDelegator {
    using FenwickTreeCheckpoints for FenwickTreeCheckpoints.Tree;

    constructor(address registry, address middleware)
        UniversalDelegator(registry, address(0), address(0), 0, middleware)
    {}

    function initializeForTest(address vault_, address roleHolder) external {
        vault = vault_;
        _prevSums.initialize(1);
        _grantRole(CREATE_SLOT_ROLE, roleHolder);
        _grantRole(SET_SIZE_ROLE, roleHolder);
        _grantRole(SWAP_SLOTS_ROLE, roleHolder);
        _grantRole(REMOVE_SLOT_ROLE, roleHolder);
    }

    function setMigrationForTest(address oldDelegator_, uint48 migrateTimestamp_) external {
        oldDelegator = oldDelegator_;
        migrateTimestamp = migrateTimestamp_;
    }

    function indexesToSyncLength() external view returns (uint256) {
        return indexesToSync.length;
    }

    function syncIndexOf(uint32 index) external view returns (uint32) {
        return indexToSyncIndex[index];
    }
}

contract UniversalDelegatorFlatInitializeHarness is UniversalDelegator {
    constructor(
        address networkRegistry,
        address vaultFactory,
        address delegatorFactory,
        uint64 entityType,
        address networkMiddlewareService
    ) UniversalDelegator(networkRegistry, vaultFactory, delegatorFactory, entityType, networkMiddlewareService) {}
}

contract UniversalDelegatorFlatCoverageTest is Test {
    using Subnetwork for address;

    UniversalDelegatorFlatRegistryMock internal registry;
    UniversalDelegatorFlatMiddlewareMock internal middlewareService;
    UniversalDelegatorFlatVaultMock internal vault;
    UniversalDelegatorFlatHarness internal delegator;

    address internal networkA = address(0x1001);
    address internal networkB = address(0x1002);
    address internal middlewareA = address(0x2001);
    address internal middlewareB = address(0x2002);
    address internal operatorA = address(0x3001);
    address internal operatorB = address(0x3002);

    function setUp() public {
        vm.warp(1);
        registry = new UniversalDelegatorFlatRegistryMock();
        middlewareService = new UniversalDelegatorFlatMiddlewareMock();
        vault = new UniversalDelegatorFlatVaultMock();
        delegator = new UniversalDelegatorFlatHarness(address(registry), address(middlewareService));
        delegator.initializeForTest(address(vault), address(this));

        middlewareService.setMiddleware(networkA, middlewareA);
        middlewareService.setMiddleware(networkB, middlewareB);
        vault.setActiveStake(1000);
    }

    function _effectiveSize(uint32 index) internal view returns (uint128) {
        IUniversalDelegator.Slot memory slot = delegator.getSlot(index);
        return
            slot.delayedTimestamp > 0 && slot.delayedTimestamp <= vm.getBlockTimestamp() ? slot.delayedSize : slot.size;
    }

    function test_MaturedDecreaseKeepsLaterSlotUnusedUntilSync() public {
        bytes32 subnetworkA = networkA.subnetwork(0);
        bytes32 subnetworkB = networkB.subnetwork(0);
        vault.setActiveStake(100);

        uint32 slotA = delegator.createSlot(subnetworkA, operatorA, 100);
        uint32 slotB = delegator.createSlot(subnetworkB, operatorB, 100);

        assertEq(slotA, 1);
        assertEq(slotB, 2);
        assertEq(delegator.stake(subnetworkA, operatorA), 100);
        assertEq(delegator.stake(subnetworkB, operatorB), 0);

        delegator.setSize(slotA, 0);
        vm.warp(vm.getBlockTimestamp() + vault.epochDuration());

        assertEq(_effectiveSize(slotA), 0);
        assertEq(delegator.stake(subnetworkB, operatorB), 0);
        assertEq(delegator.stakeForAt(subnetworkB, operatorB, 0, uint48(vm.getBlockTimestamp())), 0);

        delegator.setSize(slotB, 100);

        assertEq(delegator.stake(subnetworkB, operatorB), 100);
        assertEq(delegator.stakeForAt(subnetworkB, operatorB, 0, uint48(vm.getBlockTimestamp())), 100);
    }

    function test_PublicViewHelpersAndVersion() public {
        bytes32 subnetwork = networkA.subnetwork(0);

        uint32 slot = delegator.createSlot(subnetwork, operatorA, 100);
        uint32 zeroSlot = delegator.createSlot(networkB.subnetwork(0), operatorB, 0);

        assertEq(delegator.VERSION(), 2);
        assertEq(delegator.getBalanceAt(0, uint48(vm.getBlockTimestamp())), 1000);
        assertEq(delegator.getBalance(0), 1000);
        assertEq(delegator.getAllocatedAt(slot, 0, uint48(vm.getBlockTimestamp())), 100);
        assertEq(delegator.getAllocated(slot, 0), 100);
        assertEq(delegator.getSlotOfAt(subnetwork, operatorA, uint48(vm.getBlockTimestamp())), slot);
        assertEq(delegator.getSlot(slot).size, 100);
        assertEq(delegator.getSyncedSizeAt(subnetwork, operatorB, uint48(vm.getBlockTimestamp())), 0);
        assertEq(delegator.getSyncedSizeAt(networkB.subnetwork(0), operatorB, uint48(vm.getBlockTimestamp())), 0);
        assertEq(delegator.getSlot(zeroSlot).size, 0);
        assertEq(delegator.getSlot(zeroSlot).delayedTimestamp, 0);
        assertEq(delegator.getSlot(zeroSlot).delayedSize, 0);
    }

    function test_MulticallBubblesRevertReason() public {
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeCall(IUniversalDelegator.setSize, (uint32(1), uint128(1)));

        vm.expectRevert(IUniversalDelegator.SlotNotExists.selector);
        delegator.multicall(data);
    }

    function test_RemoveSlotRevertsWhenAllocated() public {
        uint32 slot = delegator.createSlot(networkA.subnetwork(0), operatorA, 100);

        vm.expectRevert(IUniversalDelegator.SlotAllocated.selector);
        delegator.removeSlot(slot);
    }

    function test_ResetAllocationRejectsNonNetworkOrMiddleware() public {
        bytes32 subnetwork = networkA.subnetwork(0);
        delegator.createSlot(subnetwork, operatorA, 100);

        vm.prank(address(0xABCD));
        vm.expectRevert(IUniversalDelegator.NotNetworkOrMiddleware.selector);
        delegator.resetAllocation(subnetwork, operatorA);
    }

    function test_MigrateRejectsNonVaultCaller() public {
        vm.expectRevert(IUniversalDelegator.NotVault.selector);
        delegator.migrate(address(0x1234));
    }

    function test_InitializeRejectsInvalidVaults() public {
        UniversalDelegatorFlatConfigurableRegistryMock vaultRegistry =
            new UniversalDelegatorFlatConfigurableRegistryMock();
        DelegatorFactory factory = new DelegatorFactory(address(this));
        UniversalDelegatorFlatInitializeHarness implementation = new UniversalDelegatorFlatInitializeHarness(
            address(registry),
            address(vaultRegistry),
            address(factory),
            factory.totalTypes(),
            address(middlewareService)
        );
        factory.whitelist(address(implementation));

        IUniversalDelegator.InitParams memory params = IUniversalDelegator.InitParams({
            defaultAdminRoleHolder: address(this),
            createSlotRoleHolder: address(this),
            setSizeRoleHolder: address(this),
            swapSlotsRoleHolder: address(this),
            removeSlotRoleHolder: address(this),
            setWithdrawalBufferSizeRoleHolder: address(0),
            withdrawalBufferSize: 0
        });
        bytes memory initData = abi.encode(params);

        UniversalDelegatorFlatVaultMock candidateVault = new UniversalDelegatorFlatVaultMock();

        vm.expectRevert(IUniversalDelegator.NotVault.selector);
        factory.create(0, abi.encode(address(candidateVault), initData));

        vaultRegistry.setEntity(address(candidateVault), true);
        candidateVault.setVersion(1);

        vm.expectRevert(IUniversalDelegator.OldVault.selector);
        factory.create(0, abi.encode(address(candidateVault), initData));
    }

    function test_OnSlashRejectsNonSlasher() public {
        vm.expectRevert(IUniversalDelegator.NotSlasher.selector);
        delegator.onSlash(networkA.subnetwork(0), operatorA, 1);
    }

    function test_OnSlashLegacyRejectsNonSlasher() public {
        vm.expectRevert(IUniversalDelegator.NotSlasher.selector);
        delegator.onSlashLegacy(networkA.subnetwork(0), operatorA, 1);
    }

    function test_OnSlashLegacyIgnoresMissingSlot() public {
        vault.setSlasher(address(this));

        delegator.onSlashLegacy(networkA.subnetwork(0), operatorA, 1);
    }

    function test_CreateSlotEmitsSlotMetadata() public {
        bytes32 subnetwork = networkA.subnetwork(0);

        vm.expectEmit(true, false, false, true, address(delegator));
        emit IUniversalDelegator.CreateSlot(1, subnetwork, operatorA, 100);

        delegator.createSlot(subnetwork, operatorA, 100);
    }

    function test_OnSlashSyncsMaturedPendingDecreaseBeforeSlashing() public {
        bytes32 subnetwork = networkA.subnetwork(0);
        uint32 slot = delegator.createSlot(subnetwork, operatorA, 100);

        delegator.setSize(slot, 40);
        vm.warp(vm.getBlockTimestamp() + vault.epochDuration());
        vault.setSlasher(address(this));

        delegator.onSlash(subnetwork, operatorA, 10);

        assertEq(_effectiveSize(slot), 30);
        assertEq(delegator.indexesToSyncLength(), 0);
    }

    function test_ResetAllocationEmitsSlotIndex() public {
        bytes32 subnetwork = networkA.subnetwork(0);
        uint32 slot = delegator.createSlot(subnetwork, operatorA, 100);

        vm.expectEmit(true, false, false, true, address(delegator));
        emit IUniversalDelegator.ResetAllocation(slot);

        vm.prank(middlewareA);
        delegator.resetAllocation(subnetwork, operatorA);
    }

    function test_OnSlashEmitsResolvedSlotIndex() public {
        bytes32 subnetwork = networkA.subnetwork(0);
        uint32 slot = delegator.createSlot(subnetwork, operatorA, 100);
        vault.setSlasher(address(this));

        vm.expectEmit(true, false, false, true, address(delegator));
        emit IUniversalDelegator.OnSlash(slot, 40);

        delegator.onSlash(subnetwork, operatorA, 40);
    }

    function test_OnSlashLegacyEmitsResolvedSlotIndexAndAppliedAmount() public {
        bytes32 subnetwork = networkA.subnetwork(0);
        uint32 slot = delegator.createSlot(subnetwork, operatorA, 25);
        vault.setSlasher(address(this));

        vm.expectEmit(true, false, false, true, address(delegator));
        emit IUniversalDelegator.OnSlash(slot, 25);

        delegator.onSlashLegacy(subnetwork, operatorA, 40);
    }

    function test_SetSizeSameSizeEmitsAndClearsPendingDecrease() public {
        bytes32 subnetwork = networkA.subnetwork(0);
        uint32 slot = delegator.createSlot(subnetwork, operatorA, 100);

        delegator.setSize(slot, 40);
        assertEq(delegator.indexesToSyncLength(), 1);
        assertGt(delegator.getSlot(slot).delayedTimestamp, 0);
        assertEq(delegator.getSlot(slot).delayedSize, 40);

        vm.expectEmit(true, false, false, true, address(delegator));
        emit IUniversalDelegator.SetSize(slot, 100);

        delegator.setSize(slot, 100);

        assertEq(delegator.indexesToSyncLength(), 0);
        assertEq(_effectiveSize(slot), 100);
        assertEq(delegator.getSlot(slot).delayedTimestamp, 0);
        assertEq(delegator.getSlot(slot).delayedSize, 0);
        assertEq(delegator.stake(subnetwork, operatorA), 100);
    }

    function test_DecreaseImmediatelyReleasesOnlyUnusedStakeAndDelaysAllocatedRemainder() public {
        bytes32 subnetworkA = networkA.subnetwork(0);
        bytes32 subnetworkB = networkB.subnetwork(0);
        vault.setActiveStake(40);

        uint32 slotA = delegator.createSlot(subnetworkA, operatorA, 100);
        uint32 slotB = delegator.createSlot(subnetworkB, operatorB, 100);

        assertEq(delegator.stakeFor(subnetworkA, operatorA, 0), 40);
        assertEq(delegator.stakeFor(subnetworkB, operatorB, 0), 0);

        delegator.setSize(slotA, 20);

        assertEq(_effectiveSize(slotA), 40);
        assertEq(delegator.stakeFor(subnetworkA, operatorA, 0), 40);
        assertEq(delegator.stakeFor(subnetworkB, operatorB, 0), 0);

        vm.warp(vm.getBlockTimestamp() + vault.epochDuration());

        assertEq(_effectiveSize(slotA), 20);
        assertEq(delegator.stakeFor(subnetworkB, operatorB, 0), 0);

        delegator.setSize(slotB, 100);

        assertEq(delegator.stakeFor(subnetworkB, operatorB, 0), 20);
    }

    function test_StaggeredPendingDecreasesSyncOnlyMaturedEntries() public {
        bytes32 subnetworkA = networkA.subnetwork(0);
        bytes32 subnetworkB = networkB.subnetwork(0);
        bytes32 subnetworkC = address(0x1003).subnetwork(0);
        bytes32 subnetworkD = address(0x1004).subnetwork(0);
        bytes32 subnetworkE = address(0x1005).subnetwork(0);
        address operatorC = address(0x3003);
        address operatorD = address(0x3004);
        address operatorE = address(0x3005);
        vault.setActiveStake(300);

        uint32 slotA = delegator.createSlot(subnetworkA, operatorA, 100);
        uint32 slotB = delegator.createSlot(subnetworkB, operatorB, 100);
        uint32 slotC = delegator.createSlot(subnetworkC, operatorC, 100);

        delegator.setSize(slotA, 0);
        assertEq(delegator.indexesToSyncLength(), 1);
        assertEq(delegator.syncIndexOf(slotA), 1);

        vm.warp(vm.getBlockTimestamp() + vault.epochDuration() / 2);
        delegator.setSize(slotB, 0);
        assertEq(delegator.indexesToSyncLength(), 2);
        assertGt(delegator.syncIndexOf(slotA), 0);
        assertGt(delegator.syncIndexOf(slotB), 0);

        vm.warp(1 + vault.epochDuration());
        delegator.createSlot(subnetworkD, operatorD, 0);
        assertEq(delegator.indexesToSyncLength(), 1);
        assertEq(delegator.syncIndexOf(slotA), 0);
        assertGt(delegator.syncIndexOf(slotB), 0);
        assertEq(_effectiveSize(slotA), 0);
        assertEq(_effectiveSize(slotB), 100);
        assertEq(delegator.stake(subnetworkC, operatorC), 100);

        vm.warp(1 + vault.epochDuration() + vault.epochDuration() / 2);
        delegator.createSlot(subnetworkE, operatorE, 0);
        assertEq(delegator.indexesToSyncLength(), 0);
        assertEq(delegator.syncIndexOf(slotB), 0);
        assertEq(_effectiveSize(slotB), 0);
        assertEq(delegator.stake(subnetworkC, operatorC), 100);
    }

    function test_ReplacingPendingDecreaseKeepsSingleSyncEntry() public {
        bytes32 subnetworkA = networkA.subnetwork(0);
        bytes32 subnetworkB = networkB.subnetwork(0);
        vault.setActiveStake(100);

        uint32 slotA = delegator.createSlot(subnetworkA, operatorA, 100);
        uint32 slotB = delegator.createSlot(subnetworkB, operatorB, 100);

        delegator.setSize(slotA, 50);
        assertEq(delegator.indexesToSyncLength(), 1);
        assertEq(delegator.syncIndexOf(slotA), 1);

        delegator.setSize(slotA, 80);
        assertEq(delegator.indexesToSyncLength(), 1);
        assertEq(delegator.syncIndexOf(slotA), 1);

        vm.warp(vm.getBlockTimestamp() + vault.epochDuration());
        delegator.setSize(slotB, 100);

        assertEq(delegator.indexesToSyncLength(), 0);
        assertEq(delegator.syncIndexOf(slotA), 0);
        assertEq(_effectiveSize(slotA), 80);
    }

    function test_SyncedSizeViewsTrackCreatesIncreasesAndPendingSync() public {
        bytes32 subnetworkA = networkA.subnetwork(0);
        bytes32 subnetworkB = networkB.subnetwork(0);
        vault.setActiveStake(100);

        uint32 slotA = delegator.createSlot(subnetworkA, operatorA, 100);
        uint32 slotB = delegator.createSlot(subnetworkA, operatorB, 100);
        delegator.createSlot(subnetworkB, operatorA, 30);

        uint48 createdAt = uint48(vm.getBlockTimestamp());
        assertEq(delegator.getTotalSyncedSizeAt(subnetworkA, createdAt), 200);
        assertEq(delegator.getSyncedSizeAt(subnetworkA, operatorA, createdAt), 100);
        assertEq(delegator.getSyncedSizeAt(subnetworkA, operatorB, createdAt), 100);
        assertEq(delegator.getTotalSyncedSizeAt(subnetworkB, createdAt), 30);
        assertEq(delegator.getSyncedSizeAt(subnetworkB, operatorA, createdAt), 30);

        vm.warp(createdAt + 1);
        delegator.setSize(slotB, 120);
        uint48 increasedAt = uint48(vm.getBlockTimestamp());
        assertEq(delegator.getTotalSyncedSizeAt(subnetworkA, increasedAt), 220);
        assertEq(delegator.getSyncedSizeAt(subnetworkA, operatorB, increasedAt), 120);
        assertEq(delegator.getTotalSyncedSizeAt(subnetworkB, increasedAt), 30);

        delegator.setSize(slotA, 0);
        uint48 delayedAt = uint48(vm.getBlockTimestamp());
        assertEq(delegator.indexToSyncIndex(slotA), 1);
        assertEq(delegator.getTotalSyncedSizeAt(subnetworkA, delayedAt), 220);
        assertEq(delegator.getSyncedSizeAt(subnetworkA, operatorA, delayedAt), 100);

        vm.warp(delayedAt + vault.epochDuration());
        assertEq(_effectiveSize(slotA), 0);
        assertEq(delegator.getTotalSyncedSizeAt(subnetworkA, uint48(vm.getBlockTimestamp())), 220);
        assertEq(delegator.getSyncedSizeAt(subnetworkA, operatorA, uint48(vm.getBlockTimestamp())), 100);

        delegator.setSize(slotB, 120);

        assertEq(delegator.indexToSyncIndex(slotA), 0);
        assertEq(delegator.getTotalSyncedSizeAt(subnetworkA, uint48(vm.getBlockTimestamp())), 120);
        assertEq(delegator.getSyncedSizeAt(subnetworkA, operatorA, uint48(vm.getBlockTimestamp())), 0);
        assertEq(delegator.getSyncedSizeAt(subnetworkA, operatorB, uint48(vm.getBlockTimestamp())), 120);
        assertEq(delegator.getTotalSyncedSizeAt(subnetworkB, uint48(vm.getBlockTimestamp())), 30);
    }

    function test_MaturedDecreaseCanSyncAfterEffectiveTimestamp() public {
        bytes32 subnetworkA = networkA.subnetwork(0);
        vault.setActiveStake(100);

        uint32 slotA = delegator.createSlot(subnetworkA, operatorA, 100);
        uint32 slotB = delegator.createSlot(subnetworkA, operatorB, 100);

        delegator.setSize(slotA, 0);
        vm.warp(vm.getBlockTimestamp() + vault.epochDuration() + 1);

        assertEq(_effectiveSize(slotA), 0);
        assertEq(delegator.indexToSyncIndex(slotA), 1);
        assertEq(delegator.getTotalSyncedSizeAt(subnetworkA, uint48(vm.getBlockTimestamp())), 200);

        delegator.setSize(slotB, 100);

        assertEq(delegator.indexToSyncIndex(slotA), 0);
        assertEq(delegator.getTotalSyncedSizeAt(subnetworkA, uint48(vm.getBlockTimestamp())), 100);
        assertEq(delegator.getSyncedSizeAt(subnetworkA, operatorA, uint48(vm.getBlockTimestamp())), 0);
        assertEq(delegator.getSyncedSizeAt(subnetworkA, operatorB, uint48(vm.getBlockTimestamp())), 100);
    }

    function test_SyncedSizeViewsDropResetSlotOnly() public {
        bytes32 subnetworkA = networkA.subnetwork(0);

        delegator.createSlot(subnetworkA, operatorA, 100);
        delegator.createSlot(subnetworkA, operatorB, 50);

        assertEq(delegator.getTotalSyncedSizeAt(subnetworkA, uint48(vm.getBlockTimestamp())), 150);
        assertEq(delegator.getSyncedSizeAt(subnetworkA, operatorA, uint48(vm.getBlockTimestamp())), 100);
        assertEq(delegator.getSyncedSizeAt(subnetworkA, operatorB, uint48(vm.getBlockTimestamp())), 50);

        vm.prank(middlewareA);
        delegator.resetAllocation(subnetworkA, operatorA);

        assertEq(delegator.getTotalSyncedSizeAt(subnetworkA, uint48(vm.getBlockTimestamp())), 50);
        assertEq(delegator.getSyncedSizeAt(subnetworkA, operatorA, uint48(vm.getBlockTimestamp())), 0);
        assertEq(delegator.getSyncedSizeAt(subnetworkA, operatorB, uint48(vm.getBlockTimestamp())), 50);
    }

    function test_OnSlashUpdatesSyncedSizeViews() public {
        bytes32 subnetworkA = networkA.subnetwork(0);
        vault.setSlasher(address(this));

        uint32 slotA = delegator.createSlot(subnetworkA, operatorA, 100);
        delegator.createSlot(subnetworkA, operatorB, 50);

        delegator.onSlash(subnetworkA, operatorA, 40);

        assertEq(_effectiveSize(slotA), 60);
        assertEq(delegator.getTotalSyncedSizeAt(subnetworkA, uint48(vm.getBlockTimestamp())), 110);
        assertEq(delegator.getSyncedSizeAt(subnetworkA, operatorA, uint48(vm.getBlockTimestamp())), 60);
        assertEq(delegator.getSyncedSizeAt(subnetworkA, operatorB, uint48(vm.getBlockTimestamp())), 50);
    }

    function test_SyncedSizeViewsIgnoreMaturedButUnsyncedDecreaseAfterSameSubnetworkSlash() public {
        bytes32 subnetworkA = networkA.subnetwork(0);
        vault.setActiveStake(100);
        vault.setSlasher(address(this));

        uint32 slotA = delegator.createSlot(subnetworkA, operatorA, 100);
        delegator.createSlot(subnetworkA, operatorB, 100);

        delegator.setSize(slotA, 0);
        vm.warp(vm.getBlockTimestamp() + vault.epochDuration());

        assertEq(_effectiveSize(slotA), 0);
        assertEq(delegator.indexToSyncIndex(slotA), 1);

        delegator.onSlash(subnetworkA, operatorB, 10);

        assertEq(delegator.indexToSyncIndex(slotA), 1);
        assertEq(delegator.getTotalSyncedSizeAt(subnetworkA, uint48(vm.getBlockTimestamp())), 190);
        assertEq(delegator.getSyncedSizeAt(subnetworkA, operatorA, uint48(vm.getBlockTimestamp())), 100);
        assertEq(delegator.getSyncedSizeAt(subnetworkA, operatorB, uint48(vm.getBlockTimestamp())), 90);

        delegator.setSize(2, 90);

        assertEq(delegator.indexToSyncIndex(slotA), 0);
        assertEq(delegator.getTotalSyncedSizeAt(subnetworkA, uint48(vm.getBlockTimestamp())), 90);
        assertEq(delegator.getSyncedSizeAt(subnetworkA, operatorA, uint48(vm.getBlockTimestamp())), 0);
        assertEq(delegator.getSyncedSizeAt(subnetworkA, operatorB, uint48(vm.getBlockTimestamp())), 90);
    }

    function test_OnSlashBeforePendingDecreaseKeepsDelayedTarget() public {
        bytes32 subnetworkA = networkA.subnetwork(0);
        vault.setActiveStake(40);
        vault.setSlasher(address(this));

        uint32 slotA = delegator.createSlot(subnetworkA, operatorA, 100);

        delegator.setSize(slotA, 0);
        delegator.onSlash(subnetworkA, operatorA, 10);

        assertEq(_effectiveSize(slotA), 30);
        assertEq(delegator.indexToSyncIndex(slotA), 1);
        assertEq(delegator.getTotalSyncedSizeAt(subnetworkA, uint48(vm.getBlockTimestamp())), 30);

        vm.warp(vm.getBlockTimestamp() + vault.epochDuration());

        assertEq(_effectiveSize(slotA), 0);
        assertEq(delegator.getSyncedSizeAt(subnetworkA, operatorA, uint48(vm.getBlockTimestamp())), 30);

        delegator.setSize(slotA, 0);

        assertEq(delegator.indexToSyncIndex(slotA), 0);
        assertEq(delegator.getTotalSyncedSizeAt(subnetworkA, uint48(vm.getBlockTimestamp())), 0);
        assertEq(delegator.getSyncedSizeAt(subnetworkA, operatorA, uint48(vm.getBlockTimestamp())), 0);
    }

    function test_OnSlashLegacyBeforePendingDecreaseKeepsDelayedTarget() public {
        bytes32 subnetworkA = networkA.subnetwork(0);
        vault.setActiveStake(40);
        vault.setSlasher(address(this));

        uint32 slotA = delegator.createSlot(subnetworkA, operatorA, 100);

        delegator.setSize(slotA, 0);
        delegator.onSlashLegacy(subnetworkA, operatorA, 10);

        assertEq(_effectiveSize(slotA), 30);
        assertEq(delegator.indexToSyncIndex(slotA), 1);
        assertEq(delegator.getTotalSyncedSizeAt(subnetworkA, uint48(vm.getBlockTimestamp())), 30);

        vm.warp(vm.getBlockTimestamp() + vault.epochDuration());

        assertEq(_effectiveSize(slotA), 0);
        assertEq(delegator.getSyncedSizeAt(subnetworkA, operatorA, uint48(vm.getBlockTimestamp())), 30);

        delegator.setSize(slotA, 0);

        assertEq(delegator.indexToSyncIndex(slotA), 0);
        assertEq(delegator.getTotalSyncedSizeAt(subnetworkA, uint48(vm.getBlockTimestamp())), 0);
        assertEq(delegator.getSyncedSizeAt(subnetworkA, operatorA, uint48(vm.getBlockTimestamp())), 0);
    }

    function test_ResetAfterMaturedDecreasePreservesOtherSlotHistoricalStake() public {
        bytes32 subnetworkA = networkA.subnetwork(0);
        bytes32 subnetworkB = networkB.subnetwork(0);
        vault.setActiveStake(100);

        uint32 slotA = delegator.createSlot(subnetworkA, operatorA, 100);
        delegator.createSlot(subnetworkB, operatorB, 100);
        delegator.setSize(slotA, 0);

        uint48 maturedAt = uint48(vm.getBlockTimestamp() + vault.epochDuration());
        vm.warp(maturedAt);
        assertEq(delegator.stakeForAt(subnetworkB, operatorB, 0, maturedAt), 0);

        vm.prank(middlewareA);
        delegator.resetAllocation(subnetworkA, operatorA);

        assertEq(delegator.stakeForAt(subnetworkB, operatorB, 0, maturedAt), 100);
        assertEq(delegator.stake(subnetworkA, operatorA), 0);
    }

    function test_StakeForAtUsesFinalSameBlockValueAfterMaturedDecreaseIncrease() public {
        bytes32 subnetworkA = networkA.subnetwork(0);
        vault.setActiveStake(100);

        uint32 slotA = delegator.createSlot(subnetworkA, operatorA, 100);
        delegator.setSize(slotA, 20);

        uint48 maturedAt = uint48(vm.getBlockTimestamp() + vault.epochDuration());
        vm.warp(maturedAt);

        assertEq(delegator.stakeFor(subnetworkA, operatorA, 0), 20);
        assertEq(delegator.stakeForAt(subnetworkA, operatorA, 0, maturedAt), 20);

        delegator.setSize(slotA, 100);

        assertEq(delegator.stakeFor(subnetworkA, operatorA, 0), 100);
        assertEq(delegator.stakeForAt(subnetworkA, operatorA, 0, maturedAt), 100);

        vm.warp(maturedAt + 1);

        assertEq(delegator.stakeForAt(subnetworkA, operatorA, 0, maturedAt), 100);
    }

    function test_StakeForAtPreservesPastBlockMaturedDecreaseAfterLaterIncrease() public {
        bytes32 subnetworkA = networkA.subnetwork(0);
        vault.setActiveStake(100);

        uint32 slotA = delegator.createSlot(subnetworkA, operatorA, 100);
        delegator.setSize(slotA, 20);

        uint48 maturedAt = uint48(vm.getBlockTimestamp() + vault.epochDuration());
        vm.warp(maturedAt);

        assertEq(delegator.stakeFor(subnetworkA, operatorA, 0), 20);
        assertEq(delegator.stakeForAt(subnetworkA, operatorA, 0, maturedAt), 20);

        vm.warp(maturedAt + 1);
        delegator.setSize(slotA, 100);

        assertEq(delegator.stakeFor(subnetworkA, operatorA, 0), 100);
        assertEq(delegator.stakeForAt(subnetworkA, operatorA, 0, maturedAt), 20);
    }

    function test_StakeForAtPreservesPastBlockDurationAgainstLaterIncrease() public {
        bytes32 subnetworkA = networkA.subnetwork(0);
        vault.setActiveStake(200);

        uint32 slotA = delegator.createSlot(subnetworkA, operatorA, 100);
        uint48 capturedAt = uint48(vm.getBlockTimestamp());
        uint48 duration = 5;

        assertEq(delegator.stakeForAt(subnetworkA, operatorA, duration, capturedAt), 100);

        vm.warp(capturedAt + 1);
        delegator.setSize(slotA, 150);

        assertEq(delegator.stakeFor(subnetworkA, operatorA, duration), 150);
        assertEq(delegator.stakeForAt(subnetworkA, operatorA, duration, capturedAt), 100);
    }

    function test_ResetBeforePendingDecreaseMaturesClearsFutureSyncEntry() public {
        bytes32 subnetworkA = networkA.subnetwork(0);
        bytes32 subnetworkB = networkB.subnetwork(0);
        vault.setActiveStake(100);

        uint32 slotA = delegator.createSlot(subnetworkA, operatorA, 100);
        delegator.createSlot(subnetworkB, operatorB, 100);
        delegator.setSize(slotA, 0);

        assertEq(delegator.indexesToSyncLength(), 1);
        assertEq(delegator.syncIndexOf(slotA), 1);

        vm.prank(middlewareA);
        delegator.resetAllocation(subnetworkA, operatorA);

        assertEq(delegator.indexesToSyncLength(), 0);
        assertEq(delegator.syncIndexOf(slotA), 0);

        vm.warp(vm.getBlockTimestamp() + vault.epochDuration());
        delegator.setSize(2, 100);

        assertEq(delegator.indexesToSyncLength(), 0);
        assertEq(delegator.stake(subnetworkA, operatorA), 0);
        assertEq(delegator.stake(subnetworkB, operatorB), 100);
    }

    function test_RemoveBeforePendingDecreaseMaturesClearsFutureSyncEntry() public {
        bytes32 subnetworkA = networkA.subnetwork(0);
        bytes32 subnetworkB = networkB.subnetwork(0);
        vault.setActiveStake(50);

        uint32 slotA = delegator.createSlot(subnetworkA, operatorA, 100);
        delegator.createSlot(subnetworkB, operatorB, 100);
        delegator.setSize(slotA, 0);

        assertEq(delegator.indexesToSyncLength(), 1);
        assertEq(delegator.syncIndexOf(slotA), 1);
        assertEq(delegator.stake(subnetworkA, operatorA), 50);
        assertEq(delegator.stake(subnetworkB, operatorB), 0);

        vault.setActiveStake(0);
        delegator.removeSlot(slotA);

        assertEq(delegator.indexesToSyncLength(), 0);
        assertEq(delegator.syncIndexOf(slotA), 0);

        vm.warp(vm.getBlockTimestamp() + vault.epochDuration());
        vault.setActiveStake(100);

        assertEq(delegator.stake(subnetworkA, operatorA), 0);
        assertEq(delegator.stake(subnetworkB, operatorB), 100);
    }

    function test_StakeForAtBeforeMigrationDoesNotSynthesizeLegacyStakeForAt() public {
        bytes32 subnetwork = networkA.subnetwork(0);
        UniversalDelegatorFlatLegacyMock legacy = new UniversalDelegatorFlatLegacyMock();
        legacy.setStakeAtValue(77);
        delegator.setMigrationForTest(address(legacy), 50);

        assertEq(delegator.stakeAt(subnetwork, operatorA, 49, ""), 77);
        assertEq(delegator.stakeForAt(subnetwork, operatorA, vault.epochDuration() - 1, 49), 0);
    }

    function test_OnSlashLegacyCapsToSlotSizeWhenAmountExceedsCurrentAllocation() public {
        bytes32 subnetworkA = networkA.subnetwork(0);
        bytes32 subnetworkB = networkA.subnetwork(1);
        vault.setActiveStake(10);
        vault.setSlasher(address(this));

        uint32 slotA = delegator.createSlot(subnetworkA, operatorA, 25);
        delegator.createSlot(subnetworkB, operatorB, 100);

        assertEq(delegator.stakeFor(subnetworkA, operatorA, 0), 10);
        assertEq(delegator.stakeFor(subnetworkB, operatorB, 0), 0);

        delegator.onSlashLegacy(subnetworkA, operatorA, 40);

        assertEq(_effectiveSize(slotA), 0);
        assertEq(delegator.stakeFor(subnetworkA, operatorA, 0), 0);
        assertEq(delegator.stakeFor(subnetworkB, operatorB, 0), 10);
    }

    function test_OnSlashLegacyCapsPendingDecreaseWhenAmountExceedsCurrentAllocation() public {
        bytes32 subnetworkA = networkA.subnetwork(0);
        bytes32 subnetworkB = networkA.subnetwork(1);
        vault.setActiveStake(40);
        vault.setSlasher(address(this));

        uint32 slotA = delegator.createSlot(subnetworkA, operatorA, 100);
        uint32 slotB = delegator.createSlot(subnetworkB, operatorB, 100);
        delegator.setSize(slotA, 0);

        assertEq(_effectiveSize(slotA), 40);
        assertEq(delegator.indexesToSyncLength(), 1);
        assertEq(delegator.stakeFor(subnetworkA, operatorA, 0), 40);
        assertEq(delegator.stakeFor(subnetworkB, operatorB, 0), 0);

        delegator.onSlashLegacy(subnetworkA, operatorA, 70);

        assertEq(_effectiveSize(slotA), 0);
        assertEq(delegator.stakeFor(subnetworkA, operatorA, 0), 0);
        assertEq(delegator.stakeFor(subnetworkB, operatorB, 0), 40);

        vm.warp(vm.getBlockTimestamp() + vault.epochDuration());
        delegator.setSize(slotB, 100);

        assertEq(delegator.indexesToSyncLength(), 0);
        assertEq(_effectiveSize(slotA), 0);
        assertEq(delegator.stakeFor(subnetworkB, operatorB, 0), 40);
    }

    function test_NetworkOperatorPairsAreFullyIsolated() public {
        bytes32 subnetworkA = networkA.subnetwork(0);
        bytes32 subnetworkB = networkB.subnetwork(0);

        uint32 slotA1 = delegator.createSlot(subnetworkA, operatorA, 100);
        uint32 slotA2 = delegator.createSlot(subnetworkA, operatorB, 200);
        uint32 slotB1 = delegator.createSlot(subnetworkB, operatorA, 300);

        assertEq(delegator.getSlotOf(subnetworkA, operatorA), slotA1);
        assertEq(delegator.getSlotOf(subnetworkA, operatorB), slotA2);
        assertEq(delegator.getSlotOf(subnetworkB, operatorA), slotB1);
        assertEq(delegator.getSlotOf(subnetworkB, operatorB), 0);
        assertEq(delegator.stake(subnetworkB, operatorB), 0);
        assertEq(delegator.stakeFor(subnetworkB, operatorB, 0), 0);
        assertEq(delegator.stakeAt(subnetworkB, operatorB, uint48(vm.getBlockTimestamp()), ""), 0);
        assertEq(delegator.stakeForAt(subnetworkB, operatorB, 0, uint48(vm.getBlockTimestamp())), 0);
    }

    function test_CreateSlotRevertsAlreadyAssignedForExistingPair() public {
        bytes32 subnetworkA = networkA.subnetwork(0);

        delegator.createSlot(subnetworkA, operatorA, 100);

        vm.expectRevert(IUniversalDelegator.AlreadyAssigned.selector);
        delegator.createSlot(subnetworkA, operatorA, 100);
    }

    function test_CreateSlotRevertsInvalidZeroSubnetwork() public {
        vm.expectRevert(IUniversalDelegator.InvalidNetOrOp.selector);
        delegator.createSlot(bytes32(0), operatorA, 100);
    }

    function test_CreateSlotRevertsInvalidZeroOperator() public {
        vm.expectRevert(IUniversalDelegator.InvalidNetOrOp.selector);
        delegator.createSlot(networkA.subnetwork(0), address(0), 100);
    }

    function test_SwapSlotsRevertsWrongOrderForReverseOrder() public {
        bytes32 subnetworkA = networkA.subnetwork(0);

        uint32 slotA = delegator.createSlot(subnetworkA, operatorA, 100);
        uint32 slotB = delegator.createSlot(subnetworkA, operatorB, 100);

        vm.expectRevert(IUniversalDelegator.WrongOrder.selector);
        delegator.swapSlots(slotB, slotA);
    }

    function test_SwapSlotsRevertsForPartiallyAllocatedSecondSlot() public {
        bytes32 subnetworkA = networkA.subnetwork(0);
        vault.setActiveStake(150);

        uint32 slotA = delegator.createSlot(subnetworkA, operatorA, 100);
        uint32 slotB = delegator.createSlot(subnetworkA, operatorB, 100);

        assertEq(delegator.stake(subnetworkA, operatorA), 100);
        assertEq(delegator.stake(subnetworkA, operatorB), 50);

        vm.expectRevert();
        delegator.swapSlots(slotA, slotB);
    }

    function test_SwapSlotsAllowsZeroSizeBoundarySecondSlot() public {
        bytes32 subnetworkA = networkA.subnetwork(0);
        vault.setActiveStake(100);

        uint32 slotA = delegator.createSlot(subnetworkA, operatorA, 100);
        uint32 slotB = delegator.createSlot(subnetworkA, operatorB, 0);

        assertEq(delegator.stake(subnetworkA, operatorA), 100);
        assertEq(delegator.stake(subnetworkA, operatorB), 0);

        uint48 timestamp = uint48(vm.getBlockTimestamp());
        delegator.swapSlots(slotA, slotB);

        assertEq(delegator.stake(subnetworkA, operatorA), 100);
        assertEq(delegator.stakeFor(subnetworkA, operatorA, 0), 100);
        assertEq(delegator.stakeAt(subnetworkA, operatorA, timestamp, ""), 100);
        assertEq(delegator.stakeForAt(subnetworkA, operatorA, 0, timestamp), 100);
        assertEq(delegator.stake(subnetworkA, operatorB), 0);
        assertEq(delegator.stakeFor(subnetworkA, operatorB, 0), 0);
        assertEq(delegator.stakeAt(subnetworkA, operatorB, timestamp, ""), 0);
        assertEq(delegator.stakeForAt(subnetworkA, operatorB, 0, timestamp), 0);
    }

    function test_GetSlotReturnsCurrentPositionFirst() public {
        bytes32 subnetworkA = networkA.subnetwork(0);

        uint32 slotA = delegator.createSlot(subnetworkA, operatorA, 100);
        uint32 slotB = delegator.createSlot(subnetworkA, operatorB, 100);

        delegator.swapSlots(slotA, slotB);

        IUniversalDelegator.Slot memory slot = delegator.getSlot(slotA);

        assertEq(slot.pos, 1);
        assertTrue(slot.exists);
        assertEq(slot.operator, operatorA);
        assertEq(slot.subnetwork, subnetworkA);
        assertEq(slot.size, 100);
        assertEq(slot.delayedTimestamp, 0);
        assertEq(slot.delayedSize, 0);
    }

    function test_SwapSlotsAllowsFullyAllocatedSlots() public {
        bytes32 subnetworkA = networkA.subnetwork(0);
        vault.setActiveStake(200);

        uint32 slotA = delegator.createSlot(subnetworkA, operatorA, 100);
        uint32 slotB = delegator.createSlot(subnetworkA, operatorB, 100);

        delegator.swapSlots(slotA, slotB);

        assertEq(delegator.stake(subnetworkA, operatorA), 100);
        assertEq(delegator.stake(subnetworkA, operatorB), 100);
    }

    function test_SwapSlotsAllowsUnallocatedSlots() public {
        bytes32 subnetworkA = networkA.subnetwork(0);
        vault.setActiveStake(0);

        uint32 slotA = delegator.createSlot(subnetworkA, operatorA, 100);
        uint32 slotB = delegator.createSlot(subnetworkA, operatorB, 100);

        delegator.swapSlots(slotA, slotB);

        assertEq(delegator.stake(subnetworkA, operatorA), 0);
        assertEq(delegator.stake(subnetworkA, operatorB), 0);
    }

    function test_ResetAllocationDropsOnlyTargetPair() public {
        bytes32 subnetworkA = networkA.subnetwork(0);
        vault.setActiveStake(200);

        delegator.createSlot(subnetworkA, operatorA, 100);
        delegator.createSlot(subnetworkA, operatorB, 100);

        assertEq(delegator.stake(subnetworkA, operatorA), 100);
        assertEq(delegator.stake(subnetworkA, operatorB), 100);

        vm.prank(middlewareA);
        delegator.resetAllocation(subnetworkA, operatorA);

        assertEq(delegator.stake(subnetworkA, operatorA), 0);
        assertEq(delegator.stake(subnetworkA, operatorB), 100);
    }

    function test_RemoveMiddleSlotReleasesPrefixForLaterSlot() public {
        bytes32 subnetworkA = networkA.subnetwork(0);
        bytes32 subnetworkB = networkB.subnetwork(0);
        bytes32 subnetworkC = address(0x1003).subnetwork(0);
        address operatorC = address(0x3003);
        vault.setActiveStake(100);

        delegator.createSlot(subnetworkA, operatorA, 100);
        uint32 slotB = delegator.createSlot(subnetworkB, operatorB, 100);
        delegator.createSlot(subnetworkC, operatorC, 100);

        assertEq(delegator.stake(subnetworkA, operatorA), 100);
        assertEq(delegator.stake(subnetworkB, operatorB), 0);
        assertEq(delegator.stake(subnetworkC, operatorC), 0);

        delegator.removeSlot(slotB);
        vault.setActiveStake(200);

        assertEq(delegator.stake(subnetworkB, operatorB), 0);
        assertEq(delegator.stake(subnetworkC, operatorC), 100);
    }

    function test_LastLiveSlotCanGrowBeyondWithdrawalBuffer() public {
        bytes32 subnetworkA = networkA.subnetwork(0);
        vault.setActiveStake(100);

        uint32 slotA = delegator.createSlot(subnetworkA, operatorA, 50);

        delegator.setSize(slotA, 101);

        assertEq(_effectiveSize(slotA), 101);
        assertEq(delegator.stake(subnetworkA, operatorA), 100);
    }

    function test_FullyAllocatedBoundarySlotCanGrowWithoutStealingLaterAllocation() public {
        bytes32 subnetworkA = networkA.subnetwork(0);
        vault.setActiveStake(100);

        uint32 slotA = delegator.createSlot(subnetworkA, operatorA, 100);
        delegator.createSlot(subnetworkA, operatorB, 100);

        assertEq(delegator.stake(subnetworkA, operatorA), 100);
        assertEq(delegator.stake(subnetworkA, operatorB), 0);

        delegator.setSize(slotA, 101);

        assertEq(_effectiveSize(slotA), 101);
        assertEq(delegator.stake(subnetworkA, operatorA), 100);
        assertEq(delegator.stake(subnetworkA, operatorB), 0);
    }

    function test_EarlierSlotCannotGrowByStealingLaterAllocation() public {
        bytes32 subnetworkA = networkA.subnetwork(0);
        vault.setActiveStake(150);

        uint32 slotA = delegator.createSlot(subnetworkA, operatorA, 100);
        delegator.createSlot(subnetworkA, operatorB, 100);

        assertEq(delegator.stake(subnetworkA, operatorA), 100);
        assertEq(delegator.stake(subnetworkA, operatorB), 50);

        vm.expectRevert(IUniversalDelegator.NotEnoughBalance.selector);
        delegator.setSize(slotA, 151);
    }
}
