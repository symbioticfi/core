// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {console2} from "forge-std/console2.sol";

import {UniversalDelegatorCompactNewSimulationTest} from "./UniversalDelegatorCompactNewSimulation.t.sol";

import {VaultV2} from "../../src/contracts/vault/VaultV2.sol";
import {Slasher} from "../../src/contracts/slasher/Slasher.sol";
import {VetoSlasher} from "../../src/contracts/slasher/VetoSlasher.sol";
import {UniversalSlasher} from "../../src/contracts/slasher/UniversalSlasher.sol";
import {UniversalDelegatorCompactNew} from "./UniversalDelegatorCompactNew.sol";

import {ISlasher, SLASHER_TYPE} from "../../src/interfaces/slasher/ISlasher.sol";
import {IBaseSlasher} from "../../src/interfaces/slasher/IBaseSlasher.sol";
import {IVaultConfigurator} from "../../src/interfaces/IVaultConfigurator.sol";
import {IVaultV2} from "../../src/interfaces/vault/IVaultV2.sol";
import {IUniversalSlasher, UNIVERSAL_SLASHER_TYPE} from "../../src/interfaces/slasher/IUniversalSlasher.sol";

contract UniversalDelegatorCompactNewProofSearchTest is UniversalDelegatorCompactNewSimulationTest {
    uint256 internal constant SEEDS_NO_SLASH = 80;
    uint256 internal constant STEPS_NO_SLASH = 8;
    uint256 internal constant SEEDS_WITH_SLASH = 240;
    uint256 internal constant STEPS_WITH_SLASH = 12;

    uint48[] internal waits;
    address internal slasherAddress;

    struct RefTriplet {
        uint256 stake0;
        uint256 stakeHalf;
        uint256 stakeMax;
    }

    struct SlashEffect {
        bool didSlash;
        uint256 slotIndex;
        uint256 slashAmount;
    }

    function test_searchReferenceDivergence_withoutSlash() public {
        _initWaits();
        bool found = _runSearch(false);
        assertTrue(found, "no divergence found without slash");
    }

    function test_searchReferenceSpace_withSlash() public {
        _initWaits();
        _installSlasher();
        bool found = _runSearch(true);
        assertFalse(found, "found divergence after slash in sampled space");
    }

    function test_searchSlashDoesNotReduceOwnStakeByMoreThanAmount() public {
        _initWaits();
        _installSlasher();
        bool found = _runSlashBoundSearch();
        assertFalse(found, "found slash reducing own stakeFor by more than slashed amount");
    }

    function test_seed3_slashOnlyReducesOwnStakeBySlashedAmount() public {
        _initWaits();
        _installSlasher();

        uint96[4] memory slots;
        uint128[4] memory sizes;
        address[4] memory operators;
        uint256 seed = 3;

        uint256 r0 = uint256(keccak256(abi.encode(seed, true, "init")));
        vm.warp(1000 + seed);
        _deposit(alice, (((r0 >> 8) % 241) + 180) * 1 ether);

        for (uint256 i = 0; i < 4; ++i) {
            operators[i] = address(uint160(uint256(keccak256(abi.encode(seed, "operator", i)))));
            sizes[i] = uint128((((r0 >> (32 + i * 32)) % 121) + 20) * 1 ether);
            slots[i] = delegator.createSlot(bytes32(uint256(uint160(operators[i]))), 0, false, false, sizes[i]);
        }

        for (uint256 step = 0; step < 9; ++step) {
            uint256 r = uint256(keccak256(abi.encode(seed, step, true, "step")));
            _applyAction(r, true, slots, sizes, operators);
        }

        RefTriplet memory beforeSlash = _slotTriplet(slots[0]);

        uint256 rSlash = uint256(keccak256(abi.encode(seed, uint256(9), true, "step")));
        (, SlashEffect memory effect) = _applyAction(rSlash, true, slots, sizes, operators);
        assertTrue(effect.didSlash);
        assertEq(effect.slotIndex, 0);
        assertEq(effect.slashAmount, 15 ether);

        RefTriplet memory afterSlash = _slotTriplet(slots[0]);

        assertEq(beforeSlash.stake0 - afterSlash.stake0, 15 ether);
        assertEq(beforeSlash.stakeHalf - afterSlash.stakeHalf, 15 ether);
        assertEq(beforeSlash.stakeMax - afterSlash.stakeMax, 15 ether);
    }

    function test_seed35_referenceDivergenceTimeline() public {
        uint96[4] memory slots;
        uint128[4] memory sizes = [uint128(78 ether), uint128(40 ether), uint128(85 ether), uint128(137 ether)];
        address[4] memory operators = [
            0x8b581E7ae7367E10fde04495402dA7c768F32147,
            0x736a998058a97c024f43d4a1FEa198Bf4aDbf710,
            0x5d2fACc15de7fAfcE588FC31B911D165D41b8311,
            0x09B25566e19b2b929B96d5a0e777b0f9D1045C54
        ];

        vm.warp(1035);
        _deposit(alice, 244 ether);

        for (uint256 i = 0; i < 4; ++i) {
            slots[i] = delegator.createSlot(bytes32(uint256(uint160(operators[i]))), 0, false, false, sizes[i]);
        }

        _reportReferenceCheckpoint("seed35 t0: initial state", slots, sizes);

        _withdraw(alice, 73 ether);
        _withdraw(alice, 32 ether);
        delegator.setSize(slots[1], 4 ether);
        sizes[1] = 4 ether;
        _deposit(alice, 32 ether);

        _reportReferenceCheckpoint("seed35 t1: after withdraw, withdraw, downsize slot2, deposit", slots, sizes);

        vm.warp(block.timestamp + HALF_DURATION);

        _reportReferenceCheckpoint("seed35 t2: after half-duration warp", slots, sizes);

        RefTriplet[4] memory ref = _reference(slots, sizes);
        assertEq(delegator.getAllocated(slots[2], 0), 85 ether);
        assertEq(delegator.getAllocated(slots[2], HALF_DURATION), 53 ether);
        assertEq(delegator.getAllocated(slots[2], MAX_DURATION), 53 ether);
        assertEq(ref[2].stake0, 85 ether);
        assertEq(ref[2].stakeHalf, 85 ether);
        assertEq(ref[2].stakeMax, 85 ether);
    }

    function test_seed35_underallocatesAtHalfDurationEvenWithoutActiveWithdrawals() public {
        uint96[4] memory slots;
        uint128[4] memory sizes = [uint128(78 ether), uint128(40 ether), uint128(85 ether), uint128(137 ether)];
        address[4] memory operators = [
            0x8b581E7ae7367E10fde04495402dA7c768F32147,
            0x736a998058a97c024f43d4a1FEa198Bf4aDbf710,
            0x5d2fACc15de7fAfcE588FC31B911D165D41b8311,
            0x09B25566e19b2b929B96d5a0e777b0f9D1045C54
        ];

        vm.warp(1035);
        _deposit(alice, 244 ether);

        for (uint256 i = 0; i < 4; ++i) {
            slots[i] = delegator.createSlot(bytes32(uint256(uint160(operators[i]))), 0, false, false, sizes[i]);
        }

        _withdraw(alice, 73 ether);
        _withdraw(alice, 32 ether);
        delegator.setSize(slots[1], 4 ether);
        _deposit(alice, 32 ether);

        vm.warp(block.timestamp + HALF_DURATION);

        uint256 totalHalf = delegator.getAllocated(slots[0], HALF_DURATION)
            + delegator.getAllocated(slots[1], HALF_DURATION) + delegator.getAllocated(slots[2], HALF_DURATION)
            + delegator.getAllocated(slots[3], HALF_DURATION);

        assertEq(vault.activeWithdrawalsFor(HALF_DURATION), 0);
        assertEq(vault.activeStake(), 171 ether);
        assertEq(totalHalf, 135 ether);
    }

    function _initWaits() internal {
        if (waits.length > 0) {
            return;
        }
        waits.push(0);
        waits.push(1);
        waits.push(1 days);
        waits.push(HALF_DURATION);
        waits.push(2 days);
        waits.push(MAX_DURATION);
    }

    function _installSlasher() internal {
        if (slasherAddress != address(0)) {
            return;
        }

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

        (address vault_, address delegator_, address slasher_) = vaultConfigurator.create(
            IVaultConfigurator.InitParams({
                version: vaultFactory.lastVersion(),
                owner: owner,
                vaultParams: abi.encode(
                    IVaultV2.InitParams({
                        name: "Compact Vault Slash",
                        symbol: "CVLTS",
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
                    UniversalDelegatorCompactNew.InitParams({
                        defaultAdminRoleHolder: owner, createSlotRoleHolder: owner, setSizeRoleHolder: owner
                    })
                ),
                withSlasher: true,
                slasherIndex: uint64(UNIVERSAL_SLASHER_TYPE),
                slasherParams: abi.encode(
                    IUniversalSlasher.InitParams({
                        isBurnerHook: false, vetoDuration: 1, resolverSetDelay: uint48(EPOCH_DURATION * 3)
                    })
                )
            })
        );

        vault = IVaultV2(vault_);
        delegator = UniversalDelegatorCompactNew(delegator_);
        slasherAddress = slasher_;
    }

    function _runSearch(bool withSlash) internal returns (bool found) {
        uint256 initialState = vm.snapshotState();
        uint256 seeds = withSlash ? SEEDS_WITH_SLASH : SEEDS_NO_SLASH;

        for (uint256 seed = 1; seed <= seeds; ++seed) {
            if (_runSeed(seed, withSlash)) {
                return true;
            }
            vm.revertToState(initialState);
            initialState = vm.snapshotState();
        }
    }

    function _runSeed(uint256 seed, bool withSlash) internal returns (bool found) {
        uint96[4] memory slots;
        uint128[4] memory sizes;
        address[4] memory operators;
        bool sawSlash;

        uint256 r0 = uint256(keccak256(abi.encode(seed, withSlash, "init")));
        vm.warp(1000 + seed);

        _deposit(alice, (((r0 >> 8) % 241) + 180) * 1 ether);

        for (uint256 i = 0; i < 4; ++i) {
            operators[i] = address(uint160(uint256(keccak256(abi.encode(seed, "operator", i)))));
            sizes[i] = uint128((((r0 >> (32 + i * 32)) % 121) + 20) * 1 ether);
            slots[i] = delegator.createSlot(bytes32(uint256(uint160(operators[i]))), 0, false, false, sizes[i]);
        }

        if (_checkReference(seed, type(uint256).max, type(uint256).max, false, true, slots, sizes)) {
            return true;
        }

        for (uint256 step = 0; step < (withSlash ? STEPS_WITH_SLASH : STEPS_NO_SLASH); ++step) {
            (bool foundStep, bool sawSlashNext) =
                _applyStepAndCheck(seed, step, withSlash, sawSlash, slots, sizes, operators);
            sawSlash = sawSlashNext;
            if (foundStep) {
                return true;
            }
        }
    }

    function _runSlashBoundSearch() internal returns (bool found) {
        uint256 initialState = vm.snapshotState();

        for (uint256 seed = 1; seed <= SEEDS_WITH_SLASH; ++seed) {
            if (_runSlashBoundSeed(seed)) {
                return true;
            }
            vm.revertToState(initialState);
            initialState = vm.snapshotState();
        }
    }

    function _runSlashBoundSeed(uint256 seed) internal returns (bool found) {
        uint96[4] memory slots;
        uint128[4] memory sizes;
        address[4] memory operators;

        uint256 r0 = uint256(keccak256(abi.encode(seed, true, "init")));
        vm.warp(1000 + seed);
        _deposit(alice, (((r0 >> 8) % 241) + 180) * 1 ether);

        for (uint256 i = 0; i < 4; ++i) {
            operators[i] = address(uint160(uint256(keccak256(abi.encode(seed, "operator", i)))));
            sizes[i] = uint128((((r0 >> (32 + i * 32)) % 121) + 20) * 1 ether);
            slots[i] = delegator.createSlot(bytes32(uint256(uint160(operators[i]))), 0, false, false, sizes[i]);
        }

        for (uint256 step = 0; step < STEPS_WITH_SLASH; ++step) {
            uint256 r = uint256(keccak256(abi.encode(seed, step, true, "step")));
            RefTriplet[4] memory beforeTriplets = _slotTriplets(slots);
            (uint256 op, SlashEffect memory effect) = _applyAction(r, true, slots, sizes, operators);

            if (!effect.didSlash) {
                continue;
            }

            RefTriplet[4] memory afterTriplets = _slotTriplets(slots);
            if (_checkSlashBound(
                    seed,
                    step,
                    op,
                    slots[effect.slotIndex],
                    effect.slotIndex,
                    effect.slashAmount,
                    beforeTriplets,
                    afterTriplets
                )) {
                return true;
            }
        }
    }

    function _applyStepAndCheck(
        uint256 seed,
        uint256 step,
        bool withSlash,
        bool sawSlash,
        uint96[4] memory slots,
        uint128[4] memory sizes,
        address[4] memory operators
    ) internal returns (bool found, bool sawSlashNext) {
        uint256 r = uint256(keccak256(abi.encode(seed, step, withSlash, "step")));
        (uint256 op, SlashEffect memory effect) = _applyAction(r, withSlash, slots, sizes, operators);
        sawSlashNext = sawSlash || effect.didSlash;
        found = _checkReference(seed, step, op, withSlash, !withSlash || sawSlashNext, slots, sizes);
    }

    function _applyAction(
        uint256 r,
        bool withSlash,
        uint96[4] memory slots,
        uint128[4] memory sizes,
        address[4] memory operators
    ) internal returns (uint256 op, SlashEffect memory effect) {
        op = r % (withSlash ? 6 : 5);

        if (op == 0) {
            _deposit(r % 2 == 0 ? alice : bob, ((r >> 8) % 90 + 1) * 1 ether);
            return (op, effect);
        }
        if (op == 1) {
            address user = r % 2 == 0 ? alice : bob;
            vm.prank(user);
            (bool ok,) = address(vault)
                .call(abi.encodeWithSelector(vault.withdraw.selector, user, ((r >> 8) % 90 + 1) * 1 ether));
            ok;
            return (op, effect);
        }
        if (op == 2 || op == 3) {
            uint256 idx = (r >> 16) % 4;
            uint128 cur = sizes[idx];
            uint128 newSize = op == 2
                ? uint128((uint256(cur) * ((r >> 24) % 11)) / 10)
                : cur + uint128((((r >> 24) % 40) + 1) * 1 ether);
            (bool ok,) =
                address(delegator).call(abi.encodeWithSelector(delegator.setSize.selector, slots[idx], newSize));
            if (ok) {
                sizes[idx] = newSize;
            }
            return (op, effect);
        }
        if (op == 4) {
            vm.warp(block.timestamp + waits[(r >> 32) % waits.length]);
            return (op, effect);
        }

        return (op, _applySlash(r, slots, sizes, operators));
    }

    function _applySlash(uint256 r, uint96[4] memory slots, uint128[4] memory sizes, address[4] memory operators)
        internal
        returns (SlashEffect memory effect)
    {
        uint256 idx = (r >> 16) % 4;
        uint256 requested = ((r >> 24) % 70 + 1) * 1 ether;
        uint256 slotStake = delegator.getAllocated(slots[idx], 0);
        uint256 slashAmount = _min3(requested, slotStake, vault.activeStake() + vault.activeWithdrawalsFor(0));

        if (slashAmount == 0) {
            return effect;
        }

        uint256 pending0 = delegator.getPending(slots[idx], 0);
        uint256 pendingSlashed = pending0 > slashAmount ? slashAmount : pending0;
        uint256 sizeSlashed = slashAmount - pendingSlashed;
        if (sizeSlashed > sizes[idx]) {
            sizeSlashed = sizes[idx];
        }

        vm.startPrank(slasherAddress);
        delegator.onSlash(bytes32(0), operators[idx], slashAmount, "");
        VaultV2(address(vault)).onSlash(slashAmount, false);
        vm.stopPrank();

        sizes[idx] -= uint128(sizeSlashed);
        effect.didSlash = true;
        effect.slotIndex = idx;
        effect.slashAmount = slashAmount;
        return effect;
    }

    function _slotTriplets(uint96[4] memory slots) internal view returns (RefTriplet[4] memory out) {
        for (uint256 i = 0; i < 4; ++i) {
            out[i] = _slotTriplet(slots[i]);
        }
    }

    function _slotTriplet(uint96 slot) internal view returns (RefTriplet memory out) {
        out.stake0 = delegator.getAllocated(slot, 0);
        out.stakeHalf = delegator.getAllocated(slot, HALF_DURATION);
        out.stakeMax = delegator.getAllocated(slot, MAX_DURATION);
    }

    function _checkSlashBound(
        uint256 seed,
        uint256 step,
        uint256 op,
        uint96 slot,
        uint256 slotIndex,
        uint256 slashAmount,
        RefTriplet[4] memory before,
        RefTriplet[4] memory afterTriplets
    ) internal view returns (bool found) {
        uint256[3] memory beforeVals = [
            before[slotIndex].stake0, before[slotIndex].stakeHalf, before[slotIndex].stakeMax
        ];
        uint256[3] memory afterVals =
            [afterTriplets[slotIndex].stake0, afterTriplets[slotIndex].stakeHalf, afterTriplets[slotIndex].stakeMax];
        uint48[3] memory ds = [uint48(0), HALF_DURATION, MAX_DURATION];

        for (uint256 i = 0; i < 3; ++i) {
            uint256 drop = beforeVals[i] > afterVals[i] ? beforeVals[i] - afterVals[i] : 0;
            if (drop > slashAmount) {
                console2.log("seed", seed);
                console2.log("step", step);
                console2.log("label", _opName(op, true));
                console2.log("slot", slot);
                console2.log("duration", ds[i]);
                console2.log("beforeStake", beforeVals[i]);
                console2.log("afterStake", afterVals[i]);
                console2.log("slashAmount", slashAmount);
                return true;
            }
        }
    }

    function _checkReference(
        uint256 seed,
        uint256 step,
        uint256 op,
        bool withSlash,
        bool shouldCheck,
        uint96[4] memory slots,
        uint128[4] memory sizes
    ) internal view returns (bool found) {
        if (!shouldCheck && step != type(uint256).max) {
            return false;
        }

        RefTriplet[4] memory ref = _reference(slots, sizes);

        for (uint256 i = 0; i < 4; ++i) {
            uint256 actual0 = delegator.getAllocated(slots[i], 0);
            uint256 actualHalf = delegator.getAllocated(slots[i], HALF_DURATION);
            uint256 actualMax = delegator.getAllocated(slots[i], MAX_DURATION);

            if (actual0 != ref[i].stake0 || actualHalf != ref[i].stakeHalf || actualMax != ref[i].stakeMax) {
                string memory label = step == type(uint256).max ? "initial" : _opName(op, withSlash);
                console2.log("seed", seed);
                console2.log("step", step);
                console2.log("label", label);
                console2.log("timestamp", block.timestamp);
                console2.log("slot", i + 1);
                console2.log("actual0", actual0);
                console2.log("actualHalf", actualHalf);
                console2.log("actualMax", actualMax);
                console2.log("ref0", ref[i].stake0);
                console2.log("refHalf", ref[i].stakeHalf);
                console2.log("refMax", ref[i].stakeMax);
                return true;
            }
        }
    }

    function _reportReferenceCheckpoint(string memory label, uint96[4] memory slots, uint128[4] memory sizes)
        internal
        view
    {
        RefTriplet[4] memory ref = _reference(slots, sizes);

        console2.log("checkpoint", label);
        console2.log("timestamp", block.timestamp);
        console2.log("activeStake", vault.activeStake());
        console2.log("activeWithdrawals0", vault.activeWithdrawalsFor(0));
        console2.log("activeWithdrawalsHalf", vault.activeWithdrawalsFor(HALF_DURATION));
        console2.log("activeWithdrawalsMax", vault.activeWithdrawalsFor(MAX_DURATION));

        for (uint256 i = 0; i < 4; ++i) {
            console2.log("slot", i + 1);
            console2.log("size", sizes[i]);
            console2.log("pending0", delegator.getPending(slots[i], 0));
            console2.log("pendingHalf", delegator.getPending(slots[i], HALF_DURATION));
            console2.log("pendingMax", delegator.getPending(slots[i], MAX_DURATION));
            console2.log("actual0", delegator.getAllocated(slots[i], 0));
            console2.log("actualHalf", delegator.getAllocated(slots[i], HALF_DURATION));
            console2.log("actualMax", delegator.getAllocated(slots[i], MAX_DURATION));
            console2.log("ref0", ref[i].stake0);
            console2.log("refHalf", ref[i].stakeHalf);
            console2.log("refMax", ref[i].stakeMax);
        }
    }

    function _reference(uint96[4] memory slots, uint128[4] memory sizes)
        internal
        view
        returns (RefTriplet[4] memory ref)
    {
        uint48[3] memory durations = [uint48(0), HALF_DURATION, MAX_DURATION];
        uint256[4][3] memory raw;

        for (uint256 d = 0; d < durations.length; ++d) {
            uint256 remaining = vault.activeStake() + vault.activeWithdrawalsFor(durations[d]);
            for (uint256 i = 0; i < 4; ++i) {
                uint256 own = uint256(sizes[i]) + delegator.getPending(slots[i], durations[d]);
                raw[d][i] = own > remaining ? remaining : own;
                remaining -= raw[d][i];
            }
        }

        for (uint256 i = 0; i < 4; ++i) {
            ref[i].stake0 = raw[0][i];
            ref[i].stakeHalf = raw[1][i] > ref[i].stake0 ? ref[i].stake0 : raw[1][i];
            ref[i].stakeMax = raw[2][i] > ref[i].stakeHalf ? ref[i].stakeHalf : raw[2][i];
        }
    }

    function _opName(uint256 op, bool withSlash) internal pure returns (string memory) {
        if (op == 0) return "deposit";
        if (op == 1) return "withdraw";
        if (op == 2) return "setSizeDown";
        if (op == 3) return "setSizeUp";
        if (op == 4) return "warp";
        if (withSlash && op == 5) return "slash";
        return "unknown";
    }

    function _min3(uint256 a, uint256 b, uint256 c) internal pure returns (uint256) {
        uint256 m = a < b ? a : b;
        return m < c ? m : c;
    }
}
