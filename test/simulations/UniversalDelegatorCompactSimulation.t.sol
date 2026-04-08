// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

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
import {NetworkRestakeDelegator} from "../../src/contracts/delegator/NetworkRestakeDelegator.sol";
import {FullRestakeDelegator} from "../../src/contracts/delegator/FullRestakeDelegator.sol";
import {OperatorSpecificDelegator} from "../../src/contracts/delegator/OperatorSpecificDelegator.sol";
import {OperatorNetworkSpecificDelegator} from "../../src/contracts/delegator/OperatorNetworkSpecificDelegator.sol";
import {UniversalDelegatorCompact} from "./UniversalDelegatorCompact.sol";

import {IVaultV2} from "../../src/interfaces/vault/IVaultV2.sol";
import {IVaultConfigurator} from "../../src/interfaces/IVaultConfigurator.sol";
import {UNIVERSAL_DELEGATOR_TYPE} from "../../src/interfaces/delegator/IUniversalDelegator.sol";

import {Token} from "../mocks/Token.sol";
import {MockRewards} from "../mocks/MockRewards.sol";
import {CoreV2StakeForInvariantHelper} from "../helpers/CoreV2StakeForInvariantHelper.sol";

contract UniversalDelegatorCompactSimulationTest is Test, CoreV2StakeForInvariantHelper {
    uint48 internal constant EPOCH_DURATION = 3 days;
    uint48 internal constant HALF_DURATION = EPOCH_DURATION / 2;
    uint48 internal constant MAX_DURATION = EPOCH_DURATION - 1;

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
    UniversalDelegatorCompact internal delegator;

    struct StakeTimelineSnapshot {
        uint48 timestamp;
        uint256 activeStake;
        uint256 activeWithdrawals0;
        uint256 activeWithdrawalsHalf;
        uint256 activeWithdrawalsMaxDuration;
        uint256 stakeFor0;
        uint256 stakeForHalf;
        uint256 stakeForMaxDuration;
    }

    function setUp() public {
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

        address compactDelegatorImpl = address(
            new UniversalDelegatorCompact(address(vaultFactory), address(delegatorFactory), UNIVERSAL_DELEGATOR_TYPE)
        );
        delegatorFactory.whitelist(compactDelegatorImpl);

        collateral = new Token("Token");
        vaultConfigurator =
            new VaultConfigurator(address(vaultFactory), address(delegatorFactory), address(slasherFactory));

        (address vault_, address delegator_,) = vaultConfigurator.create(
            IVaultConfigurator.InitParams({
                version: vaultFactory.lastVersion(),
                owner: owner,
                vaultParams: abi.encode(
                    IVaultV2.InitParams({
                        name: "Compact Vault",
                        symbol: "CVLT",
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
                    UniversalDelegatorCompact.InitParams({
                        defaultAdminRoleHolder: owner, createSlotRoleHolder: owner, setSizeRoleHolder: owner
                    })
                ),
                withSlasher: false,
                slasherIndex: 0,
                slasherParams: ""
            })
        );

        vault = IVaultV2(vault_);
        delegator = UniversalDelegatorCompact(delegator_);
    }

    function test_simulationTimeline_depositWithdrawCreateSlotSetSize_overTwoEpochs() public {
        uint48 baseTimestamp = 1;
        vm.warp(baseTimestamp);

        _deposit(alice, 1000 ether);
        uint96 slot1 = delegator.createSlot(bytes32(0), 0, false, false, uint128(400 ether));
        uint96 slot2;
        uint96 slot3;

        StakeTimelineSnapshot memory s0 = _snapshotStakeTimeline(slot1);
        _reportStakeTimeline("t0: first deposit + first slot", s0);
        _reportStakeForThreeSlots("t0", slot1, slot2, slot3);
        _reportPendingForThreeSlots("t0", slot1, slot2, slot3);
        _assertStakeForInvariantForThreeSlots(address(vault), address(delegator), slot1, slot2, slot3, EPOCH_DURATION);

        vm.warp(baseTimestamp + 1 days);
        _deposit(bob, 250 ether);
        slot2 = delegator.createSlot(bytes32(0), 0, false, false, uint128(250 ether));
        delegator.setSize(slot1, uint128(520 ether));
        _withdraw(alice, 180 ether);

        StakeTimelineSnapshot memory s1 = _snapshotStakeTimeline(slot1);
        _reportStakeTimeline("t1: second deposit + second slot + size up + withdraw", s1);
        _reportStakeForThreeSlots("t1", slot1, slot2, slot3);
        _reportPendingForThreeSlots("t1", slot1, slot2, slot3);
        _assertStakeForInvariantForThreeSlots(address(vault), address(delegator), slot1, slot2, slot3, EPOCH_DURATION);

        vm.warp(baseTimestamp + 2 days);
        slot3 = delegator.createSlot(bytes32(0), 0, false, false, uint128(120 ether));
        delegator.setSize(slot2, uint128(320 ether));
        _deposit(alice, 90 ether);
        _withdraw(bob, 110 ether);

        StakeTimelineSnapshot memory s2 = _snapshotStakeTimeline(slot1);
        _reportStakeTimeline("t2: third slot + size up + deposit + withdraw", s2);
        _reportStakeForThreeSlots("t2", slot1, slot2, slot3);
        _reportPendingForThreeSlots("t2", slot1, slot2, slot3);
        _assertStakeForInvariantForThreeSlots(address(vault), address(delegator), slot1, slot2, slot3, EPOCH_DURATION);

        vm.warp(baseTimestamp + EPOCH_DURATION + 1 days);
        delegator.setSize(slot1, uint128(460 ether));
        delegator.setSize(slot3, uint128(160 ether));
        _deposit(bob, 70 ether);
        _withdraw(alice, 90 ether);

        StakeTimelineSnapshot memory s3 = _snapshotStakeTimeline(slot1);
        _reportStakeTimeline("t3: after one epoch + size updates + deposit + withdraw", s3);
        _reportStakeForThreeSlots("t3", slot1, slot2, slot3);
        _reportPendingForThreeSlots("t3", slot1, slot2, slot3);
        _assertStakeForInvariantForThreeSlots(address(vault), address(delegator), slot1, slot2, slot3, EPOCH_DURATION);

        vm.warp(baseTimestamp + 2 * EPOCH_DURATION + 1 days);
        delegator.setSize(slot2, uint128(260 ether));
        delegator.setSize(slot3, uint128(100 ether));
        _deposit(alice, 40 ether);
        _withdraw(bob, 60 ether);

        StakeTimelineSnapshot memory s4 = _snapshotStakeTimeline(slot1);
        _reportStakeTimeline("t4: after two epochs + more size updates + deposit + withdraw", s4);
        _reportStakeForThreeSlots("t4", slot1, slot2, slot3);
        _reportPendingForThreeSlots("t4", slot1, slot2, slot3);
        _assertStakeForInvariantForThreeSlots(address(vault), address(delegator), slot1, slot2, slot3, EPOCH_DURATION);

        assertTrue(_hasDiversity(s0.activeStake, s1.activeStake, s2.activeStake, s3.activeStake, s4.activeStake));
        assertTrue(
            _hasDiversity(
                s0.activeWithdrawals0,
                s1.activeWithdrawals0,
                s2.activeWithdrawals0,
                s3.activeWithdrawals0,
                s4.activeWithdrawals0
            )
        );
        assertTrue(
            _hasDiversity(
                s0.activeWithdrawalsHalf,
                s1.activeWithdrawalsHalf,
                s2.activeWithdrawalsHalf,
                s3.activeWithdrawalsHalf,
                s4.activeWithdrawalsHalf
            )
        );
        assertTrue(_hasDiversity(s0.stakeFor0, s1.stakeFor0, s2.stakeFor0, s3.stakeFor0, s4.stakeFor0));
        assertTrue(
            _hasDiversity(
                s0.stakeForMaxDuration,
                s1.stakeForMaxDuration,
                s2.stakeForMaxDuration,
                s3.stakeForMaxDuration,
                s4.stakeForMaxDuration
            )
        );
    }

    function test_simulationTimeline_trackSecondSlot_withNetOutflowAtEnd() public {
        uint48 baseTimestamp = 11;
        vm.warp(baseTimestamp);

        _deposit(alice, 130 ether);
        uint96 slot1 = delegator.createSlot(bytes32(0), 0, false, false, uint128(80 ether));
        uint96 slot2 = delegator.createSlot(bytes32(0), 0, false, false, uint128(50 ether));

        StakeTimelineSnapshot memory s0 = _snapshotStakeTimeline(slot2);
        _reportStakeTimeline("alt t0: first deposit + two slots (track slot2)", s0);
        _reportStakeForThreeSlots("alt t0", slot1, slot2, 0);
        _reportPendingForThreeSlots("alt t0", slot1, slot2, 0);
        _assertStakeForInvariantForThreeSlots(address(vault), address(delegator), slot1, slot2, 0, EPOCH_DURATION);

        vm.warp(baseTimestamp + 1 days);
        _deposit(bob, 70 ether);
        uint96 slot3 = delegator.createSlot(bytes32(0), 0, false, false, uint128(20 ether));
        delegator.setSize(slot2, uint128(70 ether));
        _withdraw(alice, 60 ether);

        StakeTimelineSnapshot memory s1 = _snapshotStakeTimeline(slot2);
        _reportStakeTimeline("alt t1: bob deposit + third slot + size up + withdraw", s1);
        _reportStakeForThreeSlots("alt t1", slot1, slot2, slot3);
        _reportPendingForThreeSlots("alt t1", slot1, slot2, slot3);
        _assertStakeForInvariantForThreeSlots(address(vault), address(delegator), slot1, slot2, slot3, EPOCH_DURATION);

        vm.warp(baseTimestamp + 2 days);
        delegator.setSize(slot1, uint128(90 ether));
        delegator.setSize(slot3, uint128(30 ether));
        _deposit(alice, 1 ether);
        _withdraw(bob, 25 ether);

        StakeTimelineSnapshot memory s2 = _snapshotStakeTimeline(slot2);
        _reportStakeTimeline("alt t2: size updates + small deposit + withdraw", s2);
        _reportStakeForThreeSlots("alt t2", slot1, slot2, slot3);
        _reportPendingForThreeSlots("alt t2", slot1, slot2, slot3);
        _assertStakeForInvariantForThreeSlots(address(vault), address(delegator), slot1, slot2, slot3, EPOCH_DURATION);

        vm.warp(baseTimestamp + EPOCH_DURATION + 1 days);
        delegator.setSize(slot2, uint128(55 ether));
        _deposit(bob, 1 ether);
        _withdraw(alice, 65 ether);

        StakeTimelineSnapshot memory s3 = _snapshotStakeTimeline(slot2);
        _reportStakeTimeline("alt t3: after one epoch + slot2 downsize + net outflow", s3);
        _reportStakeForThreeSlots("alt t3", slot1, slot2, slot3);
        _reportPendingForThreeSlots("alt t3", slot1, slot2, slot3);
        _assertStakeForInvariantForThreeSlots(address(vault), address(delegator), slot1, slot2, slot3, EPOCH_DURATION);

        vm.warp(baseTimestamp + 2 * EPOCH_DURATION + 1 days);
        delegator.setSize(slot3, uint128(15 ether));
        _deposit(alice, 1 ether);
        _withdraw(bob, 45 ether);

        StakeTimelineSnapshot memory s4 = _snapshotStakeTimeline(slot2);
        _reportStakeTimeline("alt t4: after two epochs + deposits less than withdrawals", s4);
        _reportStakeForThreeSlots("alt t4", slot1, slot2, slot3);
        _reportPendingForThreeSlots("alt t4", slot1, slot2, slot3);
        _assertStakeForInvariantForThreeSlots(address(vault), address(delegator), slot1, slot2, slot3, EPOCH_DURATION);

        assertTrue(_hasDiversity(s0.activeStake, s1.activeStake, s2.activeStake, s3.activeStake, s4.activeStake));
        assertTrue(
            _hasDiversity(
                s0.activeWithdrawals0,
                s1.activeWithdrawals0,
                s2.activeWithdrawals0,
                s3.activeWithdrawals0,
                s4.activeWithdrawals0
            )
        );
        assertTrue(_hasDiversity(s0.stakeFor0, s1.stakeFor0, s2.stakeFor0, s3.stakeFor0, s4.stakeFor0));
        assertTrue(
            _hasDiversity(
                s0.stakeForMaxDuration,
                s1.stakeForMaxDuration,
                s2.stakeForMaxDuration,
                s3.stakeForMaxDuration,
                s4.stakeForMaxDuration
            )
        );
        assertLt(s4.activeStake, s3.activeStake);
    }

    function test_simulationTimeline_pendingTailImpactsHalfStakeFor() public {
        uint48 baseTimestamp = 21;
        vm.warp(baseTimestamp);

        _deposit(alice, 400 ether);
        uint96 slot1 = delegator.createSlot(bytes32(0), 0, false, false, uint128(220 ether));
        uint96 slot2 = delegator.createSlot(bytes32(0), 0, false, false, uint128(120 ether));
        uint96 slot3 = delegator.createSlot(bytes32(0), 0, false, false, uint128(60 ether));
        _withdraw(alice, 150 ether);

        StakeTimelineSnapshot memory s0 = _snapshotStakeTimeline(slot1);
        _reportStakeTimeline("div t0: initial withdraw before duration window shift", s0);
        _reportStakeForThreeSlots("div t0", slot1, slot2, slot3);
        _reportPendingForThreeSlots("div t0", slot1, slot2, slot3);
        _assertStakeForInvariantForThreeSlots(address(vault), address(delegator), slot1, slot2, slot3, EPOCH_DURATION);

        vm.warp(baseTimestamp + 2 days);
        delegator.setSize(slot2, uint128(20 ether));
        delegator.setSize(slot3, uint128(10 ether));

        StakeTimelineSnapshot memory s1 = _snapshotStakeTimeline(slot1);
        _reportStakeTimeline("div t1: tail slots downsized creating pending", s1);
        _reportStakeForThreeSlots("div t1", slot1, slot2, slot3);
        _reportPendingForThreeSlots("div t1", slot1, slot2, slot3);
        _assertStakeForInvariantForThreeSlots(address(vault), address(delegator), slot1, slot2, slot3, EPOCH_DURATION);

        vm.warp(baseTimestamp + 4 days);
        StakeTimelineSnapshot memory s2 = _snapshotStakeTimeline(slot1);
        _reportStakeTimeline("div t2: pending window shifted out", s2);
        _reportStakeForThreeSlots("div t2", slot1, slot2, slot3);
        _reportPendingForThreeSlots("div t2", slot1, slot2, slot3);
        vm.expectRevert(
            abi.encodeWithSelector(
                CoreV2StakeForInvariantHelper.StakeForDecreasesWithDuration.selector,
                slot1,
                uint48(0),
                uint256(100 ether),
                HALF_DURATION,
                uint256(220 ether)
            )
        );
        this.assertStakeForInvariantForThreeSlotsExternal(slot1, slot2, slot3);

        assertEq(s0.stakeFor0, 220 ether);
        assertEq(s1.stakeFor0, 220 ether);
        assertEq(s1.stakeForHalf, 100 ether);
        assertEq(s2.stakeForHalf, 220 ether);
        assertLt(s1.stakeForHalf, s1.stakeFor0);
    }

    function test_simulationTimeline_setSizesDepositWithdraw_waitEpochMinusOne_thenZeroSize() public {
        uint48 baseTimestamp = 31;
        vm.warp(baseTimestamp);

        uint96 slot1 = delegator.createSlot(bytes32(0), 0, false, false, 0);
        uint96 slot2 = delegator.createSlot(bytes32(0), 0, false, false, 0);
        uint96 slot3 = delegator.createSlot(bytes32(0), 0, false, false, 0);

        delegator.setSize(slot1, uint128(100 ether));
        delegator.setSize(slot2, uint128(100 ether));
        delegator.setSize(slot3, uint128(100 ether));

        _deposit(alice, 100 ether);
        StakeTimelineSnapshot memory s0 = _snapshotStakeTimeline(slot1);
        _reportStakeTimeline("zero t0: setSizes(100) + deposit(100)", s0);
        _reportStakeForThreeSlots("zero t0", slot1, slot2, slot3);
        _reportPendingForThreeSlots("zero t0", slot1, slot2, slot3);
        _assertStakeForInvariantForThreeSlots(address(vault), address(delegator), slot1, slot2, slot3, EPOCH_DURATION);

        _withdraw(alice, 100 ether);
        StakeTimelineSnapshot memory s1 = _snapshotStakeTimeline(slot1);
        _reportStakeTimeline("zero t1: withdraw(100)", s1);
        _reportStakeForThreeSlots("zero t1", slot1, slot2, slot3);
        _reportPendingForThreeSlots("zero t1", slot1, slot2, slot3);
        _assertStakeForInvariantForThreeSlots(address(vault), address(delegator), slot1, slot2, slot3, EPOCH_DURATION);

        vm.warp(baseTimestamp + EPOCH_DURATION - 1);
        delegator.setSize(slot1, 0);
        StakeTimelineSnapshot memory s2 = _snapshotStakeTimeline(slot1);
        _reportStakeTimeline("zero t2: wait(epoch-1) + setSize(slot1,0)", s2);
        _reportStakeForThreeSlots("zero t2", slot1, slot2, slot3);
        _reportPendingForThreeSlots("zero t2", slot1, slot2, slot3);

        vm.warp(baseTimestamp + EPOCH_DURATION);
        StakeTimelineSnapshot memory s3 = _snapshotStakeTimeline(slot1);
        _reportStakeTimeline("zero t3: wait(1)", s3);
        _reportStakeForThreeSlots("zero t3", slot1, slot2, slot3);
        _reportPendingForThreeSlots("zero t3", slot1, slot2, slot3);

        assertTrue(_hasDiversity(s0.activeStake, s1.activeStake, s2.activeStake, s3.activeStake, s3.activeStake));
        assertTrue(
            _hasDiversity(
                s0.activeWithdrawals0,
                s1.activeWithdrawals0,
                s2.activeWithdrawals0,
                s3.activeWithdrawals0,
                s3.activeWithdrawals0
            )
        );
        assertTrue(
            _hasDiversity(
                s0.stakeForMaxDuration,
                s1.stakeForMaxDuration,
                s2.stakeForMaxDuration,
                s3.stakeForMaxDuration,
                s3.stakeForMaxDuration
            )
        );
        assertLt(s1.activeStake, s0.activeStake);
    }

    function test_simulationTimeline_preSwapPendingWindow_withoutSwap() public {
        uint48 baseTimestamp = 41 days;
        uint48 maxDuration = MAX_DURATION;
        vm.warp(baseTimestamp);

        _deposit(alice, 50 ether);
        uint96 slot1 = delegator.createSlot(bytes32(0), 0, false, false, uint128(50 ether));
        uint96 slot2 = delegator.createSlot(bytes32(0), 0, false, false, uint128(50 ether));
        _withdraw(alice, 50 ether);

        StakeTimelineSnapshot memory s0 = _snapshotStakeTimeline(slot1);
        _reportStakeTimeline("pre t0: deposit(50) + createSlot(50,50) + withdraw(50)", s0);
        _reportStakeForThreeSlots("pre t0", slot1, slot2, 0);
        _reportPendingForThreeSlots("pre t0", slot1, slot2, 0);
        _assertStakeForInvariantForThreeSlots(address(vault), address(delegator), slot1, slot2, 0, EPOCH_DURATION);

        vm.warp(baseTimestamp + EPOCH_DURATION - 1);
        delegator.setSize(slot1, 0);

        StakeTimelineSnapshot memory s1 = _snapshotStakeTimeline(slot1);
        _reportStakeTimeline("pre t1: wait(epoch-1) + setSize(slot1,0)", s1);
        _reportStakeForThreeSlots("pre t1", slot1, slot2, 0);
        _reportPendingForThreeSlots("pre t1", slot1, slot2, 0);

        assertEq(_stakeFor(slot1, HALF_DURATION), 50 ether);
        assertEq(_stakeFor(slot1, maxDuration), 50 ether);
        assertEq(_stakeFor(slot2, maxDuration), 0);
        assertEq(delegator.getPending(slot1, maxDuration), 50 ether);
        vm.expectRevert(
            abi.encodeWithSelector(
                CoreV2StakeForInvariantHelper.StakeForSumExceedsCapacity.selector,
                HALF_DURATION,
                uint256(50 ether),
                uint256(0)
            )
        );
        this.assertStakeForInvariantForThreeSlotsExternal(slot1, slot2, 0);

        vm.warp(baseTimestamp + EPOCH_DURATION);

        StakeTimelineSnapshot memory s2 = _snapshotStakeTimeline(slot1);
        _reportStakeTimeline("pre t2: wait(1s) to epoch boundary", s2);
        _reportStakeForThreeSlots("pre t2", slot1, slot2, 0);
        _reportPendingForThreeSlots("pre t2", slot1, slot2, 0);

        assertEq(s0.activeStake, 0);
        assertEq(s1.activeStake, 0);
        assertEq(s2.activeStake, 0);

        assertEq(s0.activeWithdrawals0, 50 ether);
        assertEq(s0.activeWithdrawalsHalf, 50 ether);
        assertEq(s0.activeWithdrawalsMaxDuration, 50 ether);

        assertEq(_stakeFor(slot1, 0), 50 ether);
        assertEq(_stakeFor(slot1, HALF_DURATION), 50 ether);
        assertEq(_stakeFor(slot2, 0), 0);
        assertEq(_stakeFor(slot1, maxDuration), 0);
        assertEq(_stakeFor(slot2, maxDuration), 0);

        assertEq(delegator.getPending(slot1, 0), 50 ether);
        assertEq(delegator.getPending(slot1, maxDuration), 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                CoreV2StakeForInvariantHelper.StakeForSumExceedsCapacity.selector, 0, uint256(50 ether), uint256(0)
            )
        );
        this.assertStakeForInvariantForThreeSlotsExternal(slot1, slot2, 0);
    }

    function test_simulationTimeline_middleGrowth_canStillStealTailStake() public {
        uint48 baseTimestamp = 81;
        vm.warp(baseTimestamp);

        _deposit(alice, 130 ether);
        uint96 slot1 = delegator.createSlot(bytes32(0), 0, false, false, uint128(80 ether));
        uint96 slot2 = delegator.createSlot(bytes32(0), 0, false, false, uint128(50 ether));

        vm.warp(baseTimestamp + 1 days);
        _deposit(bob, 70 ether);
        uint96 slot3 = delegator.createSlot(bytes32(0), 0, false, false, uint128(20 ether));
        delegator.setSize(slot2, uint128(70 ether));
        _withdraw(alice, 60 ether);

        vm.warp(baseTimestamp + 2 days);
        delegator.setSize(slot3, uint128(30 ether));
        _deposit(alice, 1 ether);
        _withdraw(bob, 25 ether);

        StakeTimelineSnapshot memory s0 = _snapshotStakeTimeline(slot3);
        _reportStakeTimeline("cross t0: tail slot before middle growth", s0);
        _reportStakeForThreeSlots("cross t0", slot1, slot2, slot3);
        _reportPendingForThreeSlots("cross t0", slot1, slot2, slot3);
        _assertStakeForInvariantForThreeSlots(address(vault), address(delegator), slot1, slot2, slot3, EPOCH_DURATION);

        vm.expectRevert(UniversalDelegatorCompact.NotEnoughAvailable.selector);
        delegator.setSize(slot2, uint128(95 ether));

        assertEq(s0.stakeFor0, 30 ether);
        assertEq(s0.stakeForHalf, 30 ether);
        assertEq(s0.stakeForMaxDuration, 0);
    }

    function test_simulationTimeline_firstGrowth_canStillStealLongDurationFromMiddleSlot() public {
        uint48 baseTimestamp = 91;
        vm.warp(baseTimestamp);

        _deposit(alice, 130 ether);
        uint96 slot1 = delegator.createSlot(bytes32(0), 0, false, false, uint128(80 ether));
        uint96 slot2 = delegator.createSlot(bytes32(0), 0, false, false, uint128(50 ether));

        vm.warp(baseTimestamp + 1 days);
        _deposit(bob, 70 ether);
        uint96 slot3 = delegator.createSlot(bytes32(0), 0, false, false, uint128(20 ether));
        delegator.setSize(slot2, uint128(70 ether));
        _withdraw(alice, 60 ether);

        vm.warp(baseTimestamp + 2 days);
        delegator.setSize(slot3, uint128(30 ether));
        _deposit(alice, 1 ether);
        _withdraw(bob, 25 ether);

        StakeTimelineSnapshot memory s0 = _snapshotStakeTimeline(slot2);
        _reportStakeTimeline("cross2 t0: middle slot before first-slot growth", s0);
        _reportStakeForThreeSlots("cross2 t0", slot1, slot2, slot3);
        _reportPendingForThreeSlots("cross2 t0", slot1, slot2, slot3);
        _assertStakeForInvariantForThreeSlots(address(vault), address(delegator), slot1, slot2, slot3, EPOCH_DURATION);

        delegator.setSize(slot1, uint128(101 ether));

        StakeTimelineSnapshot memory s1 = _snapshotStakeTimeline(slot2);
        _reportStakeTimeline("cross2 t1: first-slot growth steals middle maxDuration stake", s1);
        _reportStakeForThreeSlots("cross2 t1", slot1, slot2, slot3);
        _reportPendingForThreeSlots("cross2 t1", slot1, slot2, slot3);
        _assertStakeForInvariantForThreeSlots(address(vault), address(delegator), slot1, slot2, slot3, EPOCH_DURATION);

        assertEq(s0.stakeFor0, 70 ether);
        assertEq(s0.stakeForHalf, 70 ether);
        assertEq(s0.stakeForMaxDuration, 61 ether);
        assertEq(s1.stakeFor0, 70 ether);
        assertEq(s1.stakeForHalf, 70 ether);
        assertEq(s1.stakeForMaxDuration, 40 ether);
        assertEq(s0.timestamp, s1.timestamp);
        assertEq(s1.stakeFor0, s0.stakeFor0);
        assertEq(s1.stakeForHalf, s0.stakeForHalf);
        assertLt(s1.stakeForMaxDuration, s0.stakeForMaxDuration);
    }

    function test_simulationTimeline_longTermRollingEpochs_withContinuousFlows() public {
        uint48 baseTimestamp = 101;
        vm.warp(baseTimestamp);

        uint48 t0Timestamp = baseTimestamp + 5;
        uint48 t2Timestamp = t0Timestamp + EPOCH_DURATION;
        uint48 t4Timestamp = t0Timestamp + 2 * EPOCH_DURATION;
        uint48 t6Timestamp = t0Timestamp + 3 * EPOCH_DURATION;
        uint48 t8Timestamp = t0Timestamp + 4 * EPOCH_DURATION;
        uint48 t10Timestamp = t0Timestamp + 5 * EPOCH_DURATION;

        uint96[8] memory slots;
        slots[0] = delegator.createSlot(bytes32(0), 0, false, false, 0);
        slots[1] = delegator.createSlot(bytes32(0), 0, false, false, 0);
        slots[2] = delegator.createSlot(bytes32(0), 0, false, false, 0);

        vm.warp(baseTimestamp + 1);
        delegator.setSize(slots[0], uint128(220 ether));
        vm.warp(baseTimestamp + 2);
        delegator.setSize(slots[1], uint128(140 ether));
        vm.warp(baseTimestamp + 3);
        delegator.setSize(slots[2], uint128(90 ether));
        vm.warp(baseTimestamp + 4);
        _deposit(alice, 700 ether);
        vm.warp(t0Timestamp);
        _withdraw(alice, 80 ether);

        StakeTimelineSnapshot memory s0 = _snapshotStakeTimeline(slots[0]);
        uint96[] memory tracked0 = _trackedSlots(slots, 3);
        _reportStakeTimeline("roll t0: genesis setSizes + deposit + withdraw", s0);
        _reportStakeForTrackedSlots("roll t0", tracked0);
        _reportPendingForTrackedSlots("roll t0", tracked0);
        _assertStakeForInvariantForDurations(address(vault), address(delegator), tracked0, EPOCH_DURATION);

        vm.warp(t2Timestamp - 4);
        _deposit(bob, 60 ether);
        vm.warp(t2Timestamp - 3);
        _withdraw(alice, 50 ether);
        vm.warp(t2Timestamp - 2);
        slots[3] = delegator.createSlot(bytes32(0), 0, false, false, uint128(40 ether));
        vm.warp(t2Timestamp - 1);
        delegator.setSize(slots[0], uint128(240 ether));
        vm.warp(t2Timestamp);

        StakeTimelineSnapshot memory s1 = _snapshotStakeTimeline(slots[0]);
        uint96[] memory tracked1 = _trackedSlots(slots, 4);
        _reportStakeTimeline("roll t1: +1 epoch add slot4 + increase slot1 + deposit + withdraw", s1);
        _reportStakeForTrackedSlots("roll t1", tracked1);
        _reportPendingForTrackedSlots("roll t1", tracked1);
        _assertStakeForInvariantForDurations(address(vault), address(delegator), tracked1, EPOCH_DURATION);

        vm.warp(t4Timestamp - 5);
        _deposit(alice, 50 ether);
        vm.warp(t4Timestamp - 4);
        _withdraw(bob, 55 ether);
        vm.warp(t4Timestamp - 3);
        delegator.setSize(slots[1], uint128(155 ether));
        vm.warp(t4Timestamp - 2);
        delegator.setSize(slots[2], uint128(65 ether));
        vm.warp(t4Timestamp - 1);
        slots[4] = delegator.createSlot(bytes32(0), 0, false, false, uint128(110 ether));
        vm.warp(t4Timestamp);

        StakeTimelineSnapshot memory s2 = _snapshotStakeTimeline(slots[0]);
        uint96[] memory tracked2 = _trackedSlots(slots, 5);
        _reportStakeTimeline("roll t2: +2 epochs add slot5 + increase slot2 + decrease slot3 + deposit + withdraw", s2);
        _reportStakeForTrackedSlots("roll t2", tracked2);
        _reportPendingForTrackedSlots("roll t2", tracked2);
        _assertStakeForInvariantForDurations(address(vault), address(delegator), tracked2, EPOCH_DURATION);

        vm.warp(t6Timestamp - 4);
        _deposit(bob, 45 ether);
        vm.warp(t6Timestamp - 3);
        _withdraw(alice, 40 ether);
        vm.warp(t6Timestamp - 2);
        slots[5] = delegator.createSlot(bytes32(0), 0, false, false, uint128(5 ether));
        vm.warp(t6Timestamp - 1);
        delegator.setSize(slots[0], uint128(250 ether));
        vm.warp(t6Timestamp);

        StakeTimelineSnapshot memory s3 = _snapshotStakeTimeline(slots[0]);
        uint96[] memory tracked3 = _trackedSlots(slots, 6);
        _reportStakeTimeline("roll t3: +3 epochs add slot6 + increase slot1 + deposit + withdraw", s3);
        _reportStakeForTrackedSlots("roll t3", tracked3);
        _reportPendingForTrackedSlots("roll t3", tracked3);
        _assertStakeForInvariantForDurations(address(vault), address(delegator), tracked3, EPOCH_DURATION);

        vm.warp(t8Timestamp - 5);
        _deposit(alice, 55 ether);
        vm.warp(t8Timestamp - 4);
        _withdraw(bob, 50 ether);
        vm.warp(t8Timestamp - 3);
        delegator.setSize(slots[1], uint128(165 ether));
        vm.warp(t8Timestamp - 2);
        delegator.setSize(slots[3], uint128(25 ether));
        vm.warp(t8Timestamp - 1);
        slots[6] = delegator.createSlot(bytes32(0), 0, false, false, uint128(10 ether));
        vm.warp(t8Timestamp);

        StakeTimelineSnapshot memory s4 = _snapshotStakeTimeline(slots[0]);
        uint96[] memory tracked4 = _trackedSlots(slots, 7);
        _reportStakeTimeline("roll t4: +4 epochs add slot7 + increase slot2 + decrease slot4 + deposit + withdraw", s4);
        _reportStakeForTrackedSlots("roll t4", tracked4);
        _reportPendingForTrackedSlots("roll t4", tracked4);
        _assertStakeForInvariantForDurations(address(vault), address(delegator), tracked4, EPOCH_DURATION);

        vm.warp(t10Timestamp - 4);
        _deposit(bob, 35 ether);
        vm.warp(t10Timestamp - 3);
        _withdraw(alice, 30 ether);
        vm.warp(t10Timestamp - 2);
        delegator.setSize(slots[0], uint128(255 ether));
        vm.warp(t10Timestamp - 1);
        slots[7] = delegator.createSlot(bytes32(0), 0, false, false, uint128(5 ether));
        vm.warp(t10Timestamp);

        StakeTimelineSnapshot memory s5 = _snapshotStakeTimeline(slots[0]);
        uint96[] memory tracked5 = _trackedSlots(slots, 8);
        _reportStakeTimeline("roll t5: +5 epochs add slot8 + increase slot1 + deposit + withdraw", s5);
        _reportStakeForTrackedSlots("roll t5", tracked5);
        _reportPendingForTrackedSlots("roll t5", tracked5);
        _assertStakeForInvariantForDurations(address(vault), address(delegator), tracked5, EPOCH_DURATION);

        assertEq(s0.activeStake, 620 ether);
        assertEq(s1.activeStake, 630 ether);
        assertEq(s2.activeStake, 625 ether);
        assertEq(s3.activeStake, 630 ether);
        assertEq(s4.activeStake, 635 ether);
        assertEq(s5.activeStake, 640 ether);

        assertEq(s0.activeWithdrawals0, 80 ether);
        assertEq(s1.activeWithdrawals0, 50 ether);
        assertEq(s2.activeWithdrawals0, 55 ether);
        assertEq(s3.activeWithdrawals0, 40 ether);
        assertEq(s4.activeWithdrawals0, 50 ether);
        assertEq(s5.activeWithdrawals0, 30 ether);

        assertEq(s0.stakeFor0, 220 ether);
        assertEq(s1.stakeFor0, 240 ether);
        assertEq(s2.stakeFor0, 240 ether);
        assertEq(s3.stakeFor0, 250 ether);
        assertEq(s4.stakeFor0, 250 ether);
        assertEq(s5.stakeFor0, 255 ether);
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

    function assertStakeForInvariantForThreeSlotsExternal(uint96 slot1, uint96 slot2, uint96 slot3) external view {
        _assertStakeForInvariantForThreeSlots(address(vault), address(delegator), slot1, slot2, slot3, EPOCH_DURATION);
    }

    function _stakeFor(uint96 slot, uint48 duration) internal view returns (uint256) {
        return delegator.getAllocated(slot, duration);
    }

    function _snapshotStakeTimeline(uint96 slot) internal view returns (StakeTimelineSnapshot memory) {
        return StakeTimelineSnapshot({
            timestamp: uint48(block.timestamp),
            activeStake: vault.activeStake(),
            activeWithdrawals0: vault.activeWithdrawalsFor(0),
            activeWithdrawalsHalf: vault.activeWithdrawalsFor(HALF_DURATION),
            activeWithdrawalsMaxDuration: vault.activeWithdrawalsFor(MAX_DURATION),
            stakeFor0: _stakeFor(slot, 0),
            stakeForHalf: _stakeFor(slot, HALF_DURATION),
            stakeForMaxDuration: _stakeFor(slot, MAX_DURATION)
        });
    }

    function _reportStakeTimeline(string memory label, StakeTimelineSnapshot memory snapshot) internal view {
        console2.log("checkpoint", label);
        console2.log("timestamp", uint256(snapshot.timestamp));
        console2.log("activeStake()", snapshot.activeStake);
        console2.log("activeWithdrawalsFor(0)", snapshot.activeWithdrawals0);
        console2.log("activeWithdrawalsFor(half)", snapshot.activeWithdrawalsHalf);
        console2.log("activeWithdrawalsFor(maxDuration)", snapshot.activeWithdrawalsMaxDuration);
        console2.log("stakeFor(0)", snapshot.stakeFor0);
        console2.log("stakeFor(half)", snapshot.stakeForHalf);
        console2.log("stakeFor(maxDuration)", snapshot.stakeForMaxDuration);
    }

    function _reportStakeForThreeSlots(string memory label, uint96 slot1, uint96 slot2, uint96 slot3) internal view {
        console2.log("stakeForSlots", label);
        _reportStakeForOneSlot("slot1", slot1);
        _reportStakeForOneSlot("slot2", slot2);
        _reportStakeForOneSlot("slot3", slot3);
    }

    function _reportStakeForOneSlot(string memory slotLabel, uint96 slot) internal view {
        uint256 stake0 = slot > 0 ? _stakeFor(slot, 0) : 0;
        uint256 stakeHalf = slot > 0 ? _stakeFor(slot, HALF_DURATION) : 0;
        uint256 stakeMaxDuration = slot > 0 ? _stakeFor(slot, MAX_DURATION) : 0;

        console2.log("stakeForSlot", slotLabel);
        console2.log("stakeForSlot(0)", stake0);
        console2.log("stakeForSlot(half)", stakeHalf);
        console2.log("stakeForSlot(maxDuration)", stakeMaxDuration);
    }

    function _reportPendingForThreeSlots(string memory label, uint96 slot1, uint96 slot2, uint96 slot3) internal view {
        console2.log("pendingForSlots", label);
        _reportPendingForOneSlot("slot1", slot1);
        _reportPendingForOneSlot("slot2", slot2);
        _reportPendingForOneSlot("slot3", slot3);
    }

    function _reportPendingForOneSlot(string memory slotLabel, uint96 slot) internal view {
        uint256 pending0 = slot > 0 ? delegator.getPending(slot, 0) : 0;
        uint256 pendingHalf = slot > 0 ? delegator.getPending(slot, HALF_DURATION) : 0;
        uint256 pendingMaxDuration = slot > 0 ? delegator.getPending(slot, MAX_DURATION) : 0;

        console2.log("pendingForSlot", slotLabel);
        console2.log("pendingForSlot(0)", pending0);
        console2.log("pendingForSlot(half)", pendingHalf);
        console2.log("pendingForSlot(maxDuration)", pendingMaxDuration);
    }

    function _reportStakeForTrackedSlots(string memory label, uint96[] memory slots) internal view {
        console2.log("stakeForTrackedSlots", label);
        for (uint256 i = 0; i < slots.length; ++i) {
            console2.log("slotIndex", i + 1);
            console2.log("stakeForSlot(0)", _stakeFor(slots[i], 0));
            console2.log("stakeForSlot(half)", _stakeFor(slots[i], HALF_DURATION));
            console2.log("stakeForSlot(maxDuration)", _stakeFor(slots[i], MAX_DURATION));
        }
    }

    function _reportPendingForTrackedSlots(string memory label, uint96[] memory slots) internal view {
        console2.log("pendingForTrackedSlots", label);
        for (uint256 i = 0; i < slots.length; ++i) {
            console2.log("slotIndex", i + 1);
            console2.log("pendingForSlot(0)", delegator.getPending(slots[i], 0));
            console2.log("pendingForSlot(half)", delegator.getPending(slots[i], HALF_DURATION));
            console2.log("pendingForSlot(maxDuration)", delegator.getPending(slots[i], MAX_DURATION));
        }
    }

    function _trackedSlots(uint96[8] memory allSlots, uint256 count) internal pure returns (uint96[] memory slots_) {
        slots_ = new uint96[](count);
        for (uint256 i = 0; i < count; ++i) {
            slots_[i] = allSlots[i];
        }
    }

    function _hasDiversity(uint256 v1, uint256 v2, uint256 v3, uint256 v4, uint256 v5) internal pure returns (bool) {
        return !(v1 == v2 && v2 == v3 && v3 == v4 && v4 == v5);
    }
}
