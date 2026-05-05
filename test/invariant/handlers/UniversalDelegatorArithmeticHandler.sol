// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";

import {VaultFactory} from "../../../src/contracts/VaultFactory.sol";
import {DelegatorFactory} from "../../../src/contracts/DelegatorFactory.sol";
import {SlasherFactory} from "../../../src/contracts/SlasherFactory.sol";
import {VaultConfigurator} from "../../../src/contracts/VaultConfigurator.sol";
import {NetworkRegistry} from "../../../src/contracts/NetworkRegistry.sol";
import {OperatorRegistry} from "../../../src/contracts/OperatorRegistry.sol";
import {NetworkMiddlewareService} from "../../../src/contracts/service/NetworkMiddlewareService.sol";
import {OptInService} from "../../../src/contracts/service/OptInService.sol";

import {Vault as VaultV1} from "../../../src/contracts/vault/Vault.sol";
import {VaultTokenized} from "../../../src/contracts/vault/VaultTokenized.sol";
import {VaultV2} from "../../../src/contracts/vault/VaultV2.sol";
import {VaultV2Migrate} from "../../../src/contracts/vault/VaultV2Migrate.sol";
import {NetworkRestakeDelegator} from "../../../src/contracts/delegator/NetworkRestakeDelegator.sol";
import {FullRestakeDelegator} from "../../../src/contracts/delegator/FullRestakeDelegator.sol";
import {OperatorSpecificDelegator} from "../../../src/contracts/delegator/OperatorSpecificDelegator.sol";
import {OperatorNetworkSpecificDelegator} from "../../../src/contracts/delegator/OperatorNetworkSpecificDelegator.sol";
import {UniversalDelegator} from "../../../src/contracts/delegator/UniversalDelegator.sol";
import {Slasher} from "../../../src/contracts/slasher/Slasher.sol";
import {VetoSlasher} from "../../../src/contracts/slasher/VetoSlasher.sol";
import {UniversalSlasher} from "../../../src/contracts/slasher/UniversalSlasher.sol";

import {Subnetwork} from "../../../src/contracts/libraries/Subnetwork.sol";
import {Checkpoints} from "../../../src/contracts/libraries/CheckpointsV2.sol";

import {IVaultV2} from "../../../src/interfaces/vault/IVaultV2.sol";
import {IUniversalDelegator} from "../../../src/interfaces/delegator/IUniversalDelegator.sol";
import {IUniversalSlasher} from "../../../src/interfaces/slasher/IUniversalSlasher.sol";
import {IVaultConfigurator} from "../../../src/interfaces/IVaultConfigurator.sol";

import {Token} from "../../mocks/Token.sol";
import {MockRewards} from "../../mocks/MockRewards.sol";

contract UniversalDelegatorArithmeticHarness is UniversalDelegator {
    using Checkpoints for Checkpoints.Trace208;

    constructor(
        address networkRegistry,
        address vaultFactory,
        address delegatorFactory,
        uint64 entityType,
        address networkMiddlewareService
    ) UniversalDelegator(networkRegistry, vaultFactory, delegatorFactory, entityType, networkMiddlewareService) {}

    function positionOf(uint32 index) public view returns (uint32) {
        return uint32(_indexToPos[index].latest());
    }
}

contract UniversalDelegatorArithmeticHandler is Test {
    using Subnetwork for address;
    using Subnetwork for bytes32;

    error StakeForSumExceedsCapacity(uint48 duration, uint256 totalStakeFor, uint256 capacity);
    error SyncedSizeSumMismatch(
        bytes32 subnetwork, uint48 timestamp, uint256 operatorSyncedSizeSum, uint256 totalSyncedSize
    );
    error StakeForDecreasesWithDuration(
        uint32 slot, uint48 shorterDuration, uint256 shorterStakeFor, uint48 longerDuration, uint256 longerStakeFor
    );
    error StakeViewDecreased(uint32 slot, bytes4 selector, uint48 duration, uint256 beforeValue, uint256 afterValue);
    error StakeForPromiseDecreased(
        uint32 slot,
        uint48 promisedAt,
        uint48 duration,
        uint48 checkedAt,
        uint48 remainingDuration,
        uint256 promisedValue,
        uint256 actualValue
    );
    error StakeForAtObservationChanged(
        uint32 slot, uint48 timestamp, uint48 duration, uint256 observedValue, uint256 actualValue
    );
    error UnexpectedActionRevert(bytes4 selector, bytes data);

    struct StakeForPromise {
        uint32 slot;
        uint48 timestamp;
        uint48 duration;
        uint256 value;
        uint256 generation;
    }

    struct StakeForAtObservation {
        uint32 slot;
        uint48 timestamp;
        uint48 duration;
        uint256 value;
        uint256 generation;
    }

    uint256 internal constant MAX_ACTION_AMOUNT = 1_000_000 ether;
    uint256 internal constant MAX_SLOT_SIZE = 250_000 ether;
    uint256 internal constant MAX_TRACKED_TIMESTAMPS = 64;
    uint256 internal constant MAX_STAKE_FOR_PROMISES = 192;
    uint256 internal constant MAX_STAKE_FOR_AT_OBSERVATIONS = 256;
    uint8 internal constant DURATION_SAMPLES = 5;
    uint48 internal constant EPOCH_DURATION = 7 days;

    VaultFactory internal vaultFactory;
    DelegatorFactory internal delegatorFactory;
    SlasherFactory internal slasherFactory;
    VaultConfigurator internal vaultConfigurator;
    NetworkRegistry internal networkRegistry;
    OperatorRegistry internal operatorRegistry;
    NetworkMiddlewareService internal networkMiddlewareService;
    OptInService internal operatorVaultOptInService;
    OptInService internal operatorNetworkOptInService;

    Token public collateral;
    MockRewards public rewards;
    IVaultV2 public vault;
    UniversalDelegatorArithmeticHarness public delegator;
    IUniversalSlasher public slasher;

    uint32[] internal trackedSlots;
    uint48[] internal trackedTimestamps;
    bytes32[] internal knownSubnetworks;
    address[] internal knownOperators;

    mapping(uint32 slot => bool tracked) internal isTrackedSlot;
    mapping(uint32 slot => bytes32 subnetwork) internal subnetworkOfSlot;
    mapping(uint32 slot => address operator) internal operatorOfSlot;
    mapping(bytes32 subnetwork => bool known) internal isKnownSubnetwork;
    mapping(address operator => bool known) internal isKnownOperator;
    mapping(bytes32 subnetwork => mapping(address operator => uint32 slot)) internal expectedSlotOf;
    mapping(bytes32 subnetwork => address middleware) internal middlewareOf;
    mapping(address account => bool knownDepositor) internal isKnownDepositor;
    address[] internal depositors;

    uint48 internal sameBlockTimestamp;
    mapping(uint32 slot => uint256 value) internal lastStake;
    mapping(uint32 slot => uint256 value) internal lastStakeAt;
    mapping(uint32 slot => mapping(uint8 durationIndex => uint256 value)) internal lastStakeFor;
    mapping(uint32 slot => mapping(uint8 durationIndex => uint256 value)) internal lastStakeForAt;
    mapping(uint32 slot => uint256 generation) internal guaranteeGeneration;
    StakeForPromise[] internal stakeForPromises;
    StakeForAtObservation[] internal stakeForAtObservations;
    bool internal sameBlockStakeViewDecreased;
    uint32 internal sameBlockStakeViewDecreasedSlot;
    bytes4 internal sameBlockStakeViewDecreasedSelector;
    uint48 internal sameBlockStakeViewDecreasedDuration;
    uint256 internal sameBlockStakeViewBefore;
    uint256 internal sameBlockStakeViewAfter;
    bool internal stakeForPromiseDecreased;
    StakeForPromise internal decreasedStakeForPromise;
    uint48 internal decreasedStakeForPromiseCheckedAt;
    uint48 internal decreasedStakeForPromiseRemainingDuration;
    uint256 internal decreasedStakeForPromiseActualValue;
    bool internal stakeForAtObservationChanged;
    StakeForAtObservation internal changedStakeForAtObservation;
    uint256 internal changedStakeForAtObservationActualValue;
    bool internal unexpectedActionReverted;
    bytes4 internal unexpectedActionSelector;
    bytes internal unexpectedActionRevertData;

    uint256 internal nextNetworkNonce;
    uint256 internal nextOperatorNonce;
    uint256 internal nextTimestampWriteIndex;
    uint256 internal nextStakeForPromiseWriteIndex;
    uint256 internal nextStakeForAtObservationWriteIndex;

    constructor() {
        _initialize();
    }

    function getTrackedSlots() external view returns (uint32[] memory) {
        return trackedSlots;
    }

    function getTrackedTimestamps() external view returns (uint48[] memory) {
        return trackedTimestamps;
    }

    function getMiddleware(bytes32 subnetwork) external view returns (address) {
        return middlewareOf[subnetwork];
    }

    function deposit(uint256 userSeed, uint256 amount, uint256 timeJumpSeed) external {
        _warp(timeJumpSeed);

        address user = _user(userSeed);
        amount = _bound(amount, 1 ether, MAX_ACTION_AMOUNT);

        deal(address(collateral), user, amount);

        vm.startPrank(user);
        collateral.approve(address(vault), amount);
        vault.deposit(user, amount);
        vm.stopPrank();
        _rememberDepositor(user);

        _recordTimestamp();
    }

    function withdraw(uint256 userSeed, uint256 amount, uint256 timeJumpSeed) external {
        _warp(timeJumpSeed);

        address user = _selectDepositor(userSeed);
        bool withdrew;
        if (user != address(0)) {
            uint256 balance = vault.activeBalanceOf(user);
            if (balance > 0) {
                vm.prank(user);
                vault.withdraw(user, _bound(amount, 1, balance));
                withdrew = true;
            }
        }

        if (withdrew) {
            _resetSameBlockStakeViewBaseline();
        }
        _recordTimestamp();
    }

    function createRootSlot(uint256 sizeSeed, uint256 timeJumpSeed) external {
        _warp(timeJumpSeed);
        _createFreshSlot(sizeSeed);
        _recordTimestamp();
    }

    function setMaxNetworkLimit(uint256 timeJumpSeed) external {
        _warp(timeJumpSeed);
        _recordTimestamp();
    }

    function createNetworkSlot(uint256, uint256 sizeSeed, uint256 timeJumpSeed) external {
        _warp(timeJumpSeed);
        _createFreshSlot(sizeSeed);
        _recordTimestamp();
    }

    function createOperatorSlot(uint256, uint256 sizeSeed, uint256 timeJumpSeed) external {
        _warp(timeJumpSeed);
        _createFreshSlot(sizeSeed);
        _recordTimestamp();
    }

    function setSize(uint256 slotSeed, uint256 newSizeSeed, uint256 timeJumpSeed) external {
        _warp(timeJumpSeed);

        uint32 slot = _selectLiveSlot(slotSeed);
        if (slot != 0) {
            uint128 curSize = _slotSize(slot);
            uint128 newSize = uint128(_bound(newSizeSeed, 0, MAX_SLOT_SIZE));
            bool canRevertNotEnoughBalance = newSize > curSize;
            try delegator.setSize(slot, newSize) {}
            catch (bytes memory revertData) {
                if (
                    !canRevertNotEnoughBalance
                        || !_isSelector(revertData, IUniversalDelegator.NotEnoughBalance.selector)
                ) {
                    _recordUnexpectedActionRevert(UniversalDelegator.setSize.selector, revertData);
                }
            }
        }

        _recordTimestamp();
    }

    function swapSlots(uint256, uint256 leftSeed, uint256 rightSeed, uint256 timeJumpSeed) external {
        _warp(timeJumpSeed);

        uint32 left = _selectLiveSlot(leftSeed);
        uint32 right = _selectLiveSlot(rightSeed);
        if (left != 0 && right != 0 && left != right) {
            bool ordered;
            (left, right, ordered) = _orderSlotsByCurrentPosition(left, right);
            if (ordered && _canSwapSlotsWithoutRevert(left, right)) {
                try delegator.swapSlots(left, right) {}
                catch (bytes memory revertData) {
                    _recordUnexpectedActionRevert(UniversalDelegator.swapSlots.selector, revertData);
                }
            }
        }

        _recordTimestamp();
    }

    function removeSlot(uint256 slotSeed, uint256 timeJumpSeed) external {
        _warp(timeJumpSeed);

        uint32 slot = _selectRemovableLiveSlot(slotSeed);
        if (slot != 0) {
            try delegator.removeSlot(slot) {
                _dropSlotGuarantees(slot);
            } catch (bytes memory revertData) {
                _recordUnexpectedActionRevert(UniversalDelegator.removeSlot.selector, revertData);
            }
        }

        _recordTimestamp();
    }

    function resetAllocation(uint256 slotSeed, uint256 timeJumpSeed) external {
        _warp(timeJumpSeed);

        uint32 slot = _selectLiveSlot(slotSeed);
        if (slot != 0) {
            bytes32 subnetwork = subnetworkOfSlot[slot];
            address middleware = middlewareOf[subnetwork];
            if (middleware != address(0)) {
                vm.prank(middleware);
                try delegator.resetAllocation(subnetwork, operatorOfSlot[slot]) {
                    _dropSlotGuarantees(slot);
                } catch (bytes memory revertData) {
                    _recordUnexpectedActionRevert(UniversalDelegator.resetAllocation.selector, revertData);
                }
            }
        }

        _recordTimestamp();
    }

    function slash(uint256 slotSeed, uint256 amountSeed, uint256 timeJumpSeed) external {
        _warp(timeJumpSeed);

        uint32 slot = _selectLiveSlot(slotSeed);
        if (slot != 0) {
            bytes32 subnetwork = subnetworkOfSlot[slot];
            address operator = operatorOfSlot[slot];
            uint256 slashable = slasher.slashableStake(subnetwork, operator, 0, "");
            address middleware = middlewareOf[subnetwork];
            if (slashable > 0 && middleware != address(0)) {
                vm.startPrank(middleware);
                try slasher.requestSlash(subnetwork, operator, _bound(amountSeed, 1, slashable), 0, "") returns (
                    uint256 index
                ) {
                    try slasher.executeSlash(index, "") {
                        _invalidateSlotGuarantees(slot);
                    } catch (bytes memory revertData) {
                        _recordUnexpectedActionRevert(IUniversalSlasher.executeSlash.selector, revertData);
                    }
                } catch (bytes memory revertData) {
                    _recordUnexpectedActionRevert(IUniversalSlasher.requestSlash.selector, revertData);
                }
                vm.stopPrank();
            }
        }

        _recordTimestamp();
    }

    function touchMaturedDecreaseThenIncreaseSameBlock() external {
        (,, bytes32 subnetwork) = _prepareFreshSubnetwork();
        address operator = _prepareFreshOperator(subnetwork);
        uint32 slot = delegator.createSlot(subnetwork, operator, 100 ether);
        _trackSlot(slot, subnetwork, operator);

        delegator.setSize(slot, 20 ether);
        vm.warp(vm.getBlockTimestamp() + vault.epochDuration());

        _recordTimestamp();
        delegator.setSize(slot, 100 ether);
        _recordTimestamp();
    }

    function sameBlockDelayedDecrease(uint256 slotSeed, uint256 newSizeSeed) external {
        _recordTimestamp();

        uint32 slot = _selectLiveSlot(slotSeed);
        if (slot != 0) {
            uint128 curSize = _slotSize(slot);
            if (curSize > 0) {
                uint128 newSize = uint128(_bound(newSizeSeed, 0, curSize));
                try delegator.setSize(slot, newSize) {}
                catch (bytes memory revertData) {
                    _recordUnexpectedActionRevert(UniversalDelegator.setSize.selector, revertData);
                }
            }
        }

        _recordTimestamp();
    }

    function assertStakeForDurationAndCapacityInvariants() external view {
        for (uint8 i; i < DURATION_SAMPLES; ++i) {
            _assertStakeForSumLeCapacity(_durationAt(i));
        }
        _assertStakeForNonIncreasingAcrossDurations();
    }

    function assertTrackedSlotAssignmentsIsolated() external view {
        uint48 timestamp = uint48(vm.getBlockTimestamp());
        uint48 maxDuration = vault.epochDuration() - 1;

        for (uint256 i; i < trackedSlots.length; ++i) {
            uint32 slot = trackedSlots[i];
            IUniversalDelegator.Slot memory slotData = delegator.getSlot(slot);
            if (!slotData.exists) {
                continue;
            }

            bytes32 subnetwork = subnetworkOfSlot[slot];
            address operator = operatorOfSlot[slot];

            uint32 currentSlot = delegator.getSlotOf(subnetwork, operator);
            uint32 historicalSlot = delegator.getSlotOfAt(subnetwork, operator, timestamp);
            assertEq(currentSlot, slot);
            assertEq(historicalSlot, slot);
            assertEq(delegator.getAllocated(currentSlot, 0), delegator.getAllocated(slot, 0));
            assertEq(
                delegator.getAllocatedAt(historicalSlot, 0, timestamp), delegator.getAllocatedAt(slot, 0, timestamp)
            );
            assertEq(delegator.stakeFor(subnetwork, operator, maxDuration), delegator.stake(subnetwork, operator));
            assertEq(
                delegator.stakeForAt(subnetwork, operator, maxDuration, timestamp),
                delegator.stakeAt(subnetwork, operator, timestamp, "")
            );
        }

        _assertKnownPairCrossProductIsolation(timestamp);
    }

    function assertHistoricalStakeForAtCapacityInvariants() external view {
        for (uint256 i; i < trackedTimestamps.length; ++i) {
            uint48 timestamp = trackedTimestamps[i];
            for (uint8 j; j < DURATION_SAMPLES; ++j) {
                uint48 duration = _durationAt(j);
                uint256 totalStakeForAt;
                for (uint256 k; k < knownSubnetworks.length; ++k) {
                    for (uint256 l; l < knownOperators.length; ++l) {
                        totalStakeForAt += delegator.stakeForAt(
                            knownSubnetworks[k], knownOperators[l], duration, timestamp
                        );
                    }
                }

                uint256 capacity =
                    vault.activeStakeAt(timestamp, "") + vault.activeWithdrawalsForAt(duration, timestamp);
                if (totalStakeForAt > capacity) {
                    revert StakeForSumExceedsCapacity(duration, totalStakeForAt, capacity);
                }
            }
        }
    }

    function assertSyncedSizeSumsMatchTotals() external view {
        uint48 timestamp = uint48(vm.getBlockTimestamp());
        _assertSyncedSizeSumsMatchTotalsAt(timestamp);
        if (timestamp > 0) {
            _assertSyncedSizeSumsMatchTotalsAt(timestamp - 1);
        }
        _assertSyncedSizeSumsMatchTotalsAtPlusEpoch(timestamp);

        for (uint256 i; i < trackedTimestamps.length; ++i) {
            timestamp = trackedTimestamps[i];
            _assertSyncedSizeSumsMatchTotalsAt(timestamp);
            if (timestamp > 0) {
                _assertSyncedSizeSumsMatchTotalsAt(timestamp - 1);
            }
            _assertSyncedSizeSumsMatchTotalsAtPlusEpoch(timestamp);
        }
    }

    function assertNoUnexpectedActionReverts() external view {
        if (unexpectedActionReverted) {
            revert UnexpectedActionRevert(unexpectedActionSelector, unexpectedActionRevertData);
        }
    }

    function assertSameBlockStakeViewsNonDecreasing() public view {
        if (sameBlockStakeViewDecreased) {
            revert StakeViewDecreased(
                sameBlockStakeViewDecreasedSlot,
                sameBlockStakeViewDecreasedSelector,
                sameBlockStakeViewDecreasedDuration,
                sameBlockStakeViewBefore,
                sameBlockStakeViewAfter
            );
        }
    }

    function assertTemporalStakeForPromisesHold() public view {
        if (stakeForPromiseDecreased) {
            revert StakeForPromiseDecreased(
                decreasedStakeForPromise.slot,
                decreasedStakeForPromise.timestamp,
                decreasedStakeForPromise.duration,
                decreasedStakeForPromiseCheckedAt,
                decreasedStakeForPromiseRemainingDuration,
                decreasedStakeForPromise.value,
                decreasedStakeForPromiseActualValue
            );
        }

        uint48 timestamp = uint48(vm.getBlockTimestamp());
        for (uint256 i; i < stakeForPromises.length; ++i) {
            StakeForPromise storage stakePromise = stakeForPromises[i];
            if (timestamp < stakePromise.timestamp) {
                continue;
            }

            uint48 elapsed = timestamp - stakePromise.timestamp;
            if (elapsed > stakePromise.duration) {
                continue;
            }

            bytes32 subnetwork = subnetworkOfSlot[stakePromise.slot];
            address operator = operatorOfSlot[stakePromise.slot];
            if (
                expectedSlotOf[subnetwork][operator] != stakePromise.slot
                    || guaranteeGeneration[stakePromise.slot] != stakePromise.generation
            ) {
                continue;
            }
            uint48 remainingDuration = stakePromise.duration - elapsed;
            uint256 actualValue = delegator.stakeForAt(subnetwork, operator, remainingDuration, timestamp);
            if (actualValue < stakePromise.value) {
                revert StakeForPromiseDecreased(
                    stakePromise.slot,
                    stakePromise.timestamp,
                    stakePromise.duration,
                    timestamp,
                    remainingDuration,
                    stakePromise.value,
                    actualValue
                );
            }
        }
    }

    function assertHistoricalStakeForAtObservationsExact() public view {
        if (stakeForAtObservationChanged) {
            revert StakeForAtObservationChanged(
                changedStakeForAtObservation.slot,
                changedStakeForAtObservation.timestamp,
                changedStakeForAtObservation.duration,
                changedStakeForAtObservation.value,
                changedStakeForAtObservationActualValue
            );
        }

        for (uint256 i; i < stakeForAtObservations.length; ++i) {
            StakeForAtObservation storage observation = stakeForAtObservations[i];
            if (observation.timestamp >= vm.getBlockTimestamp()) {
                continue;
            }

            bytes32 subnetwork = subnetworkOfSlot[observation.slot];
            address operator = operatorOfSlot[observation.slot];
            if (
                expectedSlotOf[subnetwork][operator] != observation.slot
                    || guaranteeGeneration[observation.slot] != observation.generation
            ) {
                continue;
            }

            uint256 actualValue =
                delegator.stakeForAt(subnetwork, operator, observation.duration, observation.timestamp);
            if (actualValue != observation.value) {
                revert StakeForAtObservationChanged(
                    observation.slot, observation.timestamp, observation.duration, observation.value, actualValue
                );
            }
        }
    }

    function _initialize() internal {
        vm.warp(1);

        vaultFactory = new VaultFactory(address(this));
        delegatorFactory = new DelegatorFactory(address(this));
        slasherFactory = new SlasherFactory(address(this));
        vaultConfigurator =
            new VaultConfigurator(address(vaultFactory), address(delegatorFactory), address(slasherFactory));
        networkRegistry = new NetworkRegistry();
        operatorRegistry = new OperatorRegistry();
        networkMiddlewareService = new NetworkMiddlewareService(address(networkRegistry));
        operatorVaultOptInService =
            new OptInService(address(operatorRegistry), address(vaultFactory), "OperatorVaultOptInService");
        operatorNetworkOptInService =
            new OptInService(address(operatorRegistry), address(networkRegistry), "OperatorNetworkOptInService");
        collateral = new Token("UniversalDelegatorInvariantToken");
        rewards = new MockRewards();

        vaultFactory.whitelist(
            address(new VaultV1(address(delegatorFactory), address(slasherFactory), address(vaultFactory)))
        );
        vaultFactory.whitelist(
            address(new VaultTokenized(address(delegatorFactory), address(slasherFactory), address(vaultFactory)))
        );

        address vaultV2Migrate = address(
            new VaultV2Migrate(
                address(delegatorFactory), address(slasherFactory), address(0), address(rewards), address(0)
            )
        );
        vaultFactory.whitelist(
            address(
                new VaultV2(
                    address(delegatorFactory),
                    address(slasherFactory),
                    address(vaultFactory),
                    address(0),
                    address(rewards),
                    address(0),
                    vaultV2Migrate
                )
            )
        );

        delegatorFactory.whitelist(
            address(
                new NetworkRestakeDelegator(
                    address(networkRegistry),
                    address(vaultFactory),
                    address(operatorVaultOptInService),
                    address(operatorNetworkOptInService),
                    address(delegatorFactory),
                    delegatorFactory.totalTypes()
                )
            )
        );
        delegatorFactory.whitelist(
            address(
                new FullRestakeDelegator(
                    address(networkRegistry),
                    address(vaultFactory),
                    address(operatorVaultOptInService),
                    address(operatorNetworkOptInService),
                    address(delegatorFactory),
                    delegatorFactory.totalTypes()
                )
            )
        );
        delegatorFactory.whitelist(
            address(
                new OperatorSpecificDelegator(
                    address(operatorRegistry),
                    address(networkRegistry),
                    address(vaultFactory),
                    address(operatorVaultOptInService),
                    address(operatorNetworkOptInService),
                    address(delegatorFactory),
                    delegatorFactory.totalTypes()
                )
            )
        );
        delegatorFactory.whitelist(
            address(
                new OperatorNetworkSpecificDelegator(
                    address(operatorRegistry),
                    address(networkRegistry),
                    address(vaultFactory),
                    address(operatorVaultOptInService),
                    address(operatorNetworkOptInService),
                    address(delegatorFactory),
                    delegatorFactory.totalTypes()
                )
            )
        );
        delegatorFactory.whitelist(
            address(
                new UniversalDelegatorArithmeticHarness(
                    address(networkRegistry),
                    address(vaultFactory),
                    address(delegatorFactory),
                    delegatorFactory.totalTypes(),
                    address(networkMiddlewareService)
                )
            )
        );

        slasherFactory.whitelist(
            address(
                new Slasher(
                    address(vaultFactory),
                    address(networkMiddlewareService),
                    address(slasherFactory),
                    slasherFactory.totalTypes()
                )
            )
        );
        slasherFactory.whitelist(
            address(
                new VetoSlasher(
                    address(vaultFactory),
                    address(networkMiddlewareService),
                    address(networkRegistry),
                    address(slasherFactory),
                    slasherFactory.totalTypes()
                )
            )
        );
        slasherFactory.whitelist(
            address(
                new UniversalSlasher(
                    address(vaultFactory),
                    address(networkMiddlewareService),
                    address(networkRegistry),
                    address(slasherFactory),
                    slasherFactory.totalTypes()
                )
            )
        );

        IVaultV2.InitParams memory vaultParams = IVaultV2.InitParams({
            name: "UD Invariant Vault",
            symbol: "UDIV",
            collateral: address(collateral),
            burner: address(0xBEEF),
            epochDuration: EPOCH_DURATION,
            adapters: new address[](0),
            adaptersAllowDelay: EPOCH_DURATION + 1,
            depositWhitelist: false,
            depositorToWhitelist: address(0xBEEF),
            isDepositLimit: false,
            depositLimit: 0,
            defaultAdminRoleHolder: address(this),
            depositWhitelistSetRoleHolder: address(this),
            depositorWhitelistRoleHolder: address(this),
            isDepositLimitSetRoleHolder: address(this),
            depositLimitSetRoleHolder: address(this),
            setAdapterLimitRoleHolder: address(this),
            swapAdaptersRoleHolder: address(this),
            allocateAdapterRoleHolder: address(this),
            deallocateAdapterRoleHolder: address(this)
        });

        IUniversalDelegator.InitParams memory delegatorParams = IUniversalDelegator.InitParams({
            defaultAdminRoleHolder: address(this),
            createSlotRoleHolder: address(this),
            setSizeRoleHolder: address(this),
            swapSlotsRoleHolder: address(this),
            removeSlotRoleHolder: address(this),
            setWithdrawalBufferSizeRoleHolder: address(this),
            withdrawalBufferSize: type(uint128).max
        });

        IUniversalSlasher.InitParams memory slasherParams =
            IUniversalSlasher.InitParams({isBurnerHook: false, vetoDuration: 0, resolverSetDelay: 8 days});

        (address vault_, address delegator_, address slasher_) = vaultConfigurator.create(
            IVaultConfigurator.InitParams({
                version: vaultFactory.lastVersion(),
                owner: address(this),
                vaultParams: abi.encode(vaultParams),
                delegatorIndex: uint64(delegatorFactory.totalTypes() - 1),
                delegatorParams: abi.encode(delegatorParams),
                withSlasher: true,
                slasherIndex: uint64(slasherFactory.totalTypes() - 1),
                slasherParams: abi.encode(slasherParams)
            })
        );

        vault = IVaultV2(vault_);
        delegator = UniversalDelegatorArithmeticHarness(delegator_);
        slasher = IUniversalSlasher(slasher_);

        address bootstrapDepositor = _user(0);
        deal(address(collateral), bootstrapDepositor, 2_000_000 ether);

        vm.startPrank(bootstrapDepositor);
        collateral.approve(address(vault), 2_000_000 ether);
        vault.deposit(bootstrapDepositor, 2_000_000 ether);
        vm.stopPrank();
        _rememberDepositor(bootstrapDepositor);

        _bootstrapSharedIdentityTopology();
        _createFreshSlot(120 ether);
        _recordTimestamp();
    }

    function _createFreshSlot(uint256 sizeSeed) internal {
        (,, bytes32 subnetwork) = _prepareFreshSubnetwork();
        address operator = _prepareFreshOperator(subnetwork);
        uint128 size = uint128(_bound(sizeSeed, 0, MAX_SLOT_SIZE));

        _createSlotFor(subnetwork, operator, size);
    }

    function _bootstrapSharedIdentityTopology() internal {
        (,, bytes32 subnetwork1) = _prepareFreshSubnetwork();
        (,, bytes32 subnetwork2) = _prepareFreshSubnetwork();
        address operator1 = _prepareFreshOperator(subnetwork1);
        address operator2 = _prepareFreshOperator(subnetwork1);
        _optInOperatorToSubnetwork(operator1, subnetwork2);

        _createSlotFor(subnetwork1, operator1, 220 ether);
        _createSlotFor(subnetwork1, operator2, 160 ether);
        _createSlotFor(subnetwork2, operator1, 130 ether);
    }

    function _createSlotFor(bytes32 subnetwork, address operator, uint128 size) internal {
        uint32 slot = delegator.createSlot(subnetwork, operator, size);
        _trackSlot(slot, subnetwork, operator);
    }

    function _trackSlot(uint32 slot, bytes32 subnetwork, address operator) internal {
        if (slot == 0 || isTrackedSlot[slot]) {
            return;
        }
        isTrackedSlot[slot] = true;
        trackedSlots.push(slot);
        subnetworkOfSlot[slot] = subnetwork;
        operatorOfSlot[slot] = operator;
        expectedSlotOf[subnetwork][operator] = slot;
        _rememberSubnetwork(subnetwork);
        _rememberOperator(operator);
    }

    function _prepareFreshSubnetwork() internal returns (address network, address middleware, bytes32 subnetwork) {
        ++nextNetworkNonce;
        network = address(uint160(10_000 + nextNetworkNonce));
        middleware = address(uint160(100_000 + nextNetworkNonce));
        subnetwork = network.subnetwork(0);

        vm.startPrank(network);
        networkRegistry.registerNetwork();
        networkMiddlewareService.setMiddleware(middleware);
        vm.stopPrank();

        middlewareOf[subnetwork] = middleware;
    }

    function _prepareFreshOperator(bytes32 subnetwork) internal returns (address operator) {
        ++nextOperatorNonce;
        operator = address(uint160(1_000_000 + nextOperatorNonce));

        vm.prank(operator);
        operatorRegistry.registerOperator();

        vm.prank(operator);
        operatorVaultOptInService.optIn(address(vault));

        vm.prank(operator);
        operatorNetworkOptInService.optIn(subnetwork.network());
    }

    function _optInOperatorToSubnetwork(address operator, bytes32 subnetwork) internal {
        vm.prank(operator);
        operatorNetworkOptInService.optIn(subnetwork.network());
    }

    function _rememberSubnetwork(bytes32 subnetwork) internal {
        if (isKnownSubnetwork[subnetwork]) {
            return;
        }
        isKnownSubnetwork[subnetwork] = true;
        knownSubnetworks.push(subnetwork);
    }

    function _rememberOperator(address operator) internal {
        if (isKnownOperator[operator]) {
            return;
        }
        isKnownOperator[operator] = true;
        knownOperators.push(operator);
    }

    function _assertStakeForSumLeCapacity(uint48 duration) internal view {
        uint256 totalStakeFor;
        for (uint256 i; i < trackedSlots.length; ++i) {
            uint32 slot = trackedSlots[i];
            if (!delegator.getSlot(slot).exists) {
                continue;
            }
            totalStakeFor += delegator.getAllocated(slot, duration);
        }

        uint256 capacity = vault.activeStake() + vault.activeWithdrawalsFor(duration);
        if (totalStakeFor > capacity) {
            revert StakeForSumExceedsCapacity(duration, totalStakeFor, capacity);
        }
    }

    function _assertStakeForNonIncreasingAcrossDurations() internal view {
        for (uint256 i; i < trackedSlots.length; ++i) {
            uint32 slot = trackedSlots[i];
            if (!delegator.getSlot(slot).exists) {
                continue;
            }

            uint48 previousDuration = _durationAt(0);
            uint256 previousValue = delegator.getAllocated(slot, previousDuration);
            for (uint8 j = 1; j < DURATION_SAMPLES; ++j) {
                uint48 duration = _durationAt(j);
                uint256 value = delegator.getAllocated(slot, duration);
                if (previousValue < value) {
                    revert StakeForDecreasesWithDuration(slot, previousDuration, previousValue, duration, value);
                }
                previousDuration = duration;
                previousValue = value;
            }
        }
    }

    function _assertKnownPairCrossProductIsolation(uint48 timestamp) internal view {
        uint48 maxDuration = vault.epochDuration() - 1;
        for (uint256 i; i < knownSubnetworks.length; ++i) {
            bytes32 subnetwork = knownSubnetworks[i];
            for (uint256 j; j < knownOperators.length; ++j) {
                address operator = knownOperators[j];
                uint32 expectedSlot = expectedSlotOf[subnetwork][operator];

                assertEq(delegator.getSlotOf(subnetwork, operator), expectedSlot);
                assertEq(delegator.getSlotOfAt(subnetwork, operator, timestamp), expectedSlot);

                if (expectedSlot == 0) {
                    assertEq(delegator.stake(subnetwork, operator), 0);
                    assertEq(delegator.stakeFor(subnetwork, operator, 0), 0);
                    assertEq(delegator.stakeAt(subnetwork, operator, timestamp, ""), 0);
                    assertEq(delegator.stakeForAt(subnetwork, operator, 0, timestamp), 0);
                    continue;
                }

                uint32 currentSlot = delegator.getSlotOf(subnetwork, operator);
                uint32 historicalSlot = delegator.getSlotOfAt(subnetwork, operator, timestamp);
                assertEq(delegator.getAllocated(currentSlot, 0), delegator.getAllocated(expectedSlot, 0));
                assertEq(
                    delegator.getAllocatedAt(historicalSlot, 0, timestamp),
                    delegator.getAllocatedAt(expectedSlot, 0, timestamp)
                );
                assertEq(delegator.stakeFor(subnetwork, operator, maxDuration), delegator.stake(subnetwork, operator));
                assertEq(
                    delegator.stakeForAt(subnetwork, operator, maxDuration, timestamp),
                    delegator.stakeAt(subnetwork, operator, timestamp, "")
                );
            }
        }
    }

    function _assertSyncedSizeSumsMatchTotalsAtPlusEpoch(uint48 timestamp) internal view {
        uint48 epochDuration = vault.epochDuration();
        if (timestamp <= type(uint48).max - epochDuration) {
            _assertSyncedSizeSumsMatchTotalsAt(timestamp + epochDuration);
        }
    }

    function _assertSyncedSizeSumsMatchTotalsAt(uint48 timestamp) internal view {
        for (uint256 i; i < knownSubnetworks.length; ++i) {
            bytes32 subnetwork = knownSubnetworks[i];
            uint256 operatorSyncedSizeSum;
            for (uint256 j; j < knownOperators.length; ++j) {
                operatorSyncedSizeSum += delegator.getSyncedSizeAt(subnetwork, knownOperators[j], timestamp);
            }

            uint256 totalSyncedSize = delegator.getTotalSyncedSizeAt(subnetwork, timestamp);
            if (operatorSyncedSizeSum != totalSyncedSize) {
                revert SyncedSizeSumMismatch(subnetwork, timestamp, operatorSyncedSizeSum, totalSyncedSize);
            }
        }
    }

    function _selectLiveSlot(uint256 seed) internal view returns (uint32) {
        uint256 liveCount;
        for (uint256 i; i < trackedSlots.length; ++i) {
            if (delegator.getSlot(trackedSlots[i]).exists) {
                ++liveCount;
            }
        }
        if (liveCount == 0) {
            return 0;
        }

        uint256 target = _bound(seed, 0, liveCount - 1);
        for (uint256 i; i < trackedSlots.length; ++i) {
            uint32 slot = trackedSlots[i];
            if (!delegator.getSlot(slot).exists) {
                continue;
            }
            if (target == 0) {
                return slot;
            }
            --target;
        }

        return 0;
    }

    function _selectRemovableLiveSlot(uint256 seed) internal view returns (uint32) {
        uint256 removableCount;
        for (uint256 i; i < trackedSlots.length; ++i) {
            uint32 slot = trackedSlots[i];
            if (delegator.getSlot(slot).exists && delegator.getAllocated(slot, 0) == 0) {
                ++removableCount;
            }
        }
        if (removableCount == 0) {
            return 0;
        }

        uint256 target = _bound(seed, 0, removableCount - 1);
        for (uint256 i; i < trackedSlots.length; ++i) {
            uint32 slot = trackedSlots[i];
            if (!delegator.getSlot(slot).exists || delegator.getAllocated(slot, 0) > 0) {
                continue;
            }
            if (target == 0) {
                return slot;
            }
            --target;
        }
        return 0;
    }

    function _orderSlotsByCurrentPosition(uint32 slot1, uint32 slot2)
        internal
        view
        returns (uint32 left, uint32 right, bool ordered)
    {
        uint32 pos1 = delegator.positionOf(slot1);
        uint32 pos2 = delegator.positionOf(slot2);
        if (pos1 == pos2) {
            return (0, 0, false);
        }
        return pos1 < pos2 ? (slot1, slot2, true) : (slot2, slot1, true);
    }

    function _canSwapSlotsWithoutRevert(uint32 left, uint32 right) internal view returns (bool) {
        uint48 maxDuration = vault.epochDuration() - 1;
        return delegator.getAllocated(right, maxDuration) == _slotSize(right) || delegator.getAllocated(left, 0) == 0;
    }

    function _slotSize(uint32 slot) internal view returns (uint128) {
        return delegator.getSlot(slot).size;
    }

    function _durationAt(uint8 index) internal view returns (uint48) {
        if (index == 0) {
            return 0;
        }
        if (index == 1) {
            return vault.epochDuration() > 1 ? 1 : 0;
        }
        if (index == 2) {
            return vault.epochDuration() / 2;
        }
        if (index == 3) {
            return vault.epochDuration() - 1;
        }
        return vault.epochDuration();
    }

    function _rememberDepositor(address user) internal {
        if (isKnownDepositor[user]) {
            return;
        }
        isKnownDepositor[user] = true;
        depositors.push(user);
    }

    function _selectDepositor(uint256 seed) internal view returns (address) {
        if (depositors.length == 0) {
            return address(0);
        }
        return depositors[_bound(seed, 0, depositors.length - 1)];
    }

    function _user(uint256 seed) internal pure returns (address user) {
        user = address(uint160(10_000_000 + (seed % 1_000_000)));
    }

    function _warp(uint256 timeJumpSeed) internal {
        if (timeJumpSeed % 4 == 0) {
            return;
        }
        uint256 timeJump = _bound(timeJumpSeed, 1 hours, 14 days);
        vm.warp(vm.getBlockTimestamp() + timeJump);
    }

    function _recordTimestamp() internal {
        uint48 timestamp = uint48(vm.getBlockTimestamp());
        _recordFinalizedStakeForAtObservations(timestamp);

        if (trackedTimestamps.length < MAX_TRACKED_TIMESTAMPS) {
            trackedTimestamps.push(timestamp);
        } else {
            trackedTimestamps[nextTimestampWriteIndex] = timestamp;
            nextTimestampWriteIndex = (nextTimestampWriteIndex + 1) % MAX_TRACKED_TIMESTAMPS;
        }

        _recordSameBlockStakeViews(timestamp);
        _recordStakeForPromiseGuarantees(timestamp);
        _recordStakeForAtObservationGuarantees();
        _recordStakeForPromises(timestamp);
    }

    function _recordSameBlockStakeViews(uint48 timestamp) internal {
        bool sameBlock = sameBlockTimestamp == timestamp;
        if (!sameBlock) {
            sameBlockTimestamp = timestamp;
        }

        for (uint256 i; i < trackedSlots.length; ++i) {
            _recordSameBlockSlotViews(trackedSlots[i], timestamp, sameBlock);
        }
    }

    function _recordSameBlockSlotViews(uint32 slot, uint48 timestamp, bool sameBlock) internal {
        bytes32 subnetwork = subnetworkOfSlot[slot];
        address operator = operatorOfSlot[slot];

        uint256 stakeValue = delegator.stake(subnetwork, operator);
        if (sameBlock && stakeValue < lastStake[slot]) {
            _recordStakeViewDecrease(
                slot, delegator.stake.selector, vault.epochDuration() - 1, lastStake[slot], stakeValue
            );
        }
        lastStake[slot] = stakeValue;

        uint256 stakeAtValue = delegator.stakeAt(subnetwork, operator, timestamp, "");
        if (sameBlock && stakeAtValue < lastStakeAt[slot]) {
            _recordStakeViewDecrease(
                slot, delegator.stakeAt.selector, vault.epochDuration() - 1, lastStakeAt[slot], stakeAtValue
            );
        }
        lastStakeAt[slot] = stakeAtValue;

        for (uint8 j; j < DURATION_SAMPLES; ++j) {
            _recordSameBlockStakeForViews(slot, subnetwork, operator, j, timestamp, sameBlock);
        }
    }

    function _recordSameBlockStakeForViews(
        uint32 slot,
        bytes32 subnetwork,
        address operator,
        uint8 durationIndex,
        uint48 timestamp,
        bool sameBlock
    ) internal {
        uint48 duration = _durationAt(durationIndex);
        uint256 stakeForValue = delegator.stakeFor(subnetwork, operator, duration);
        if (sameBlock && stakeForValue < lastStakeFor[slot][durationIndex]) {
            _recordStakeViewDecrease(
                slot, delegator.stakeFor.selector, duration, lastStakeFor[slot][durationIndex], stakeForValue
            );
        }
        lastStakeFor[slot][durationIndex] = stakeForValue;

        uint256 stakeForAtValue = delegator.stakeForAt(subnetwork, operator, duration, timestamp);
        if (sameBlock && stakeForAtValue < lastStakeForAt[slot][durationIndex]) {
            _recordStakeViewDecrease(
                slot, delegator.stakeForAt.selector, duration, lastStakeForAt[slot][durationIndex], stakeForAtValue
            );
        }
        lastStakeForAt[slot][durationIndex] = stakeForAtValue;
    }

    function _recordStakeViewDecrease(
        uint32 slot,
        bytes4 selector,
        uint48 duration,
        uint256 beforeValue,
        uint256 afterValue
    ) internal {
        if (sameBlockStakeViewDecreased) {
            return;
        }
        sameBlockStakeViewDecreased = true;
        sameBlockStakeViewDecreasedSlot = slot;
        sameBlockStakeViewDecreasedSelector = selector;
        sameBlockStakeViewDecreasedDuration = duration;
        sameBlockStakeViewBefore = beforeValue;
        sameBlockStakeViewAfter = afterValue;
    }

    /// @dev Starts a fresh same-block baseline after a global vault backing mutation.
    function _resetSameBlockStakeViewBaseline() internal {
        sameBlockTimestamp = 0;
    }

    function _recordUnexpectedActionRevert(bytes4 selector, bytes memory revertData) internal {
        if (unexpectedActionReverted) {
            return;
        }
        unexpectedActionReverted = true;
        unexpectedActionSelector = selector;
        unexpectedActionRevertData = revertData;
    }

    /// @dev Returns true when revert data is exactly a selector-only custom error.
    function _isSelector(bytes memory revertData, bytes4 selector) internal pure returns (bool) {
        return revertData.length == 4 && bytes4(revertData) == selector;
    }

    function _dropSlotGuarantees(uint32 slot) internal {
        bytes32 subnetwork = subnetworkOfSlot[slot];
        address operator = operatorOfSlot[slot];
        expectedSlotOf[subnetwork][operator] = 0;
        _invalidateSlotGuarantees(slot);
    }

    function _invalidateSlotGuarantees(uint32 slot) internal {
        ++guaranteeGeneration[slot];

        lastStake[slot] = 0;
        lastStakeAt[slot] = 0;
        for (uint8 i; i < DURATION_SAMPLES; ++i) {
            lastStakeFor[slot][i] = 0;
            lastStakeForAt[slot][i] = 0;
        }
    }

    function _recordStakeForAtObservationGuarantees() internal {
        for (uint256 i; i < stakeForAtObservations.length; ++i) {
            StakeForAtObservation storage observation = stakeForAtObservations[i];
            if (observation.timestamp >= vm.getBlockTimestamp()) {
                continue;
            }

            bytes32 subnetwork = subnetworkOfSlot[observation.slot];
            address operator = operatorOfSlot[observation.slot];
            if (
                expectedSlotOf[subnetwork][operator] != observation.slot
                    || guaranteeGeneration[observation.slot] != observation.generation
            ) {
                continue;
            }

            uint256 actualValue =
                delegator.stakeForAt(subnetwork, operator, observation.duration, observation.timestamp);
            if (actualValue != observation.value) {
                _recordStakeForAtObservationChange(observation, actualValue);
            }
        }
    }

    function _recordStakeForAtObservationChange(StakeForAtObservation storage observation, uint256 actualValue)
        internal
    {
        if (stakeForAtObservationChanged) {
            return;
        }
        stakeForAtObservationChanged = true;
        changedStakeForAtObservation = StakeForAtObservation({
            slot: observation.slot,
            timestamp: observation.timestamp,
            duration: observation.duration,
            value: observation.value,
            generation: observation.generation
        });
        changedStakeForAtObservationActualValue = actualValue;
    }

    function _recordFinalizedStakeForAtObservations(uint48 timestamp) internal {
        uint48 previousTimestamp = sameBlockTimestamp;
        if (previousTimestamp != 0 && previousTimestamp < timestamp) {
            _recordStakeForAtObservations(previousTimestamp);
        }
    }

    function _recordStakeForPromiseGuarantees(uint48 timestamp) internal {
        for (uint256 i; i < stakeForPromises.length; ++i) {
            StakeForPromise storage stakePromise = stakeForPromises[i];
            if (timestamp < stakePromise.timestamp) {
                continue;
            }

            uint48 elapsed = timestamp - stakePromise.timestamp;
            if (elapsed > stakePromise.duration) {
                continue;
            }

            bytes32 subnetwork = subnetworkOfSlot[stakePromise.slot];
            address operator = operatorOfSlot[stakePromise.slot];
            if (
                expectedSlotOf[subnetwork][operator] != stakePromise.slot
                    || guaranteeGeneration[stakePromise.slot] != stakePromise.generation
            ) {
                continue;
            }
            uint48 remainingDuration = stakePromise.duration - elapsed;
            uint256 actualValue = delegator.stakeForAt(subnetwork, operator, remainingDuration, timestamp);
            if (actualValue < stakePromise.value) {
                _recordStakeForPromiseDecrease(stakePromise, timestamp, remainingDuration, actualValue);
            }
        }
    }

    function _recordStakeForPromiseDecrease(
        StakeForPromise storage stakePromise,
        uint48 checkedAt,
        uint48 remainingDuration,
        uint256 actualValue
    ) internal {
        if (stakeForPromiseDecreased) {
            return;
        }
        stakeForPromiseDecreased = true;
        decreasedStakeForPromise = StakeForPromise({
            slot: stakePromise.slot,
            timestamp: stakePromise.timestamp,
            duration: stakePromise.duration,
            value: stakePromise.value,
            generation: stakePromise.generation
        });
        decreasedStakeForPromiseCheckedAt = checkedAt;
        decreasedStakeForPromiseRemainingDuration = remainingDuration;
        decreasedStakeForPromiseActualValue = actualValue;
    }

    function _recordStakeForPromises(uint48 timestamp) internal {
        for (uint256 i; i < trackedSlots.length; ++i) {
            uint32 slot = trackedSlots[i];
            if (!delegator.getSlot(slot).exists) {
                continue;
            }

            bytes32 subnetwork = subnetworkOfSlot[slot];
            address operator = operatorOfSlot[slot];
            for (uint8 j = 1; j < DURATION_SAMPLES - 1; ++j) {
                uint48 duration = _durationAt(j);
                uint256 value = delegator.stakeFor(subnetwork, operator, duration);
                if (value == 0) {
                    continue;
                }

                StakeForPromise memory stakePromise = StakeForPromise({
                    slot: slot,
                    timestamp: timestamp,
                    duration: duration,
                    value: value,
                    generation: guaranteeGeneration[slot]
                });
                if (stakeForPromises.length < MAX_STAKE_FOR_PROMISES) {
                    stakeForPromises.push(stakePromise);
                } else {
                    stakeForPromises[nextStakeForPromiseWriteIndex] = stakePromise;
                    nextStakeForPromiseWriteIndex = (nextStakeForPromiseWriteIndex + 1) % MAX_STAKE_FOR_PROMISES;
                }
            }
        }
    }

    function _recordStakeForAtObservations(uint48 timestamp) internal {
        for (uint256 i; i < trackedSlots.length; ++i) {
            uint32 slot = trackedSlots[i];
            if (!delegator.getSlot(slot).exists) {
                continue;
            }

            bytes32 subnetwork = subnetworkOfSlot[slot];
            address operator = operatorOfSlot[slot];
            for (uint8 j; j < DURATION_SAMPLES; ++j) {
                uint48 duration = _durationAt(j);
                uint256 value = delegator.stakeForAt(subnetwork, operator, duration, timestamp);
                if (value == 0) {
                    continue;
                }

                StakeForAtObservation memory observation = StakeForAtObservation({
                    slot: slot,
                    timestamp: timestamp,
                    duration: duration,
                    value: value,
                    generation: guaranteeGeneration[slot]
                });
                if (stakeForAtObservations.length < MAX_STAKE_FOR_AT_OBSERVATIONS) {
                    stakeForAtObservations.push(observation);
                } else {
                    stakeForAtObservations[nextStakeForAtObservationWriteIndex] = observation;
                    nextStakeForAtObservationWriteIndex =
                        (nextStakeForAtObservationWriteIndex + 1) % MAX_STAKE_FOR_AT_OBSERVATIONS;
                }
            }
        }
    }
}
