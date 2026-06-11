// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {CutoffPricer} from "../../../src/contracts/adapters/ll-adapter/common/CutoffPricer.sol";
import {ICutoffPricer} from "../../../src/interfaces/adapters/ll-adapter/ICutoffPricer.sol";

contract CutoffPricerHarness is CutoffPricer {
    uint256 public price;
    uint48 public priceUpdatedAt;

    constructor(uint48 initialCutoff, uint48 initialCutoffPeriod, uint48 valuationDelay, uint48 settlementDuration)
        CutoffPricer(initialCutoff, initialCutoffPeriod, valuationDelay, settlementDuration)
    {
        __CutoffPricer_init();
    }

    function setPriceData(uint256 price_, uint48 updatedAt_) external {
        price = price_;
        priceUpdatedAt = updatedAt_;
    }

    function registerPending(uint256 key, uint256 amount) external {
        _registerPending(key, amount);
    }

    function tryFreezePending(uint256 key) external {
        _tryFreezePending(key);
    }

    function clearPending(uint256 key) external {
        _clearPending(key);
    }

    function pendingValue(uint256 key) external view returns (uint256) {
        return _pendingValue(key);
    }

    function cohortValue(uint256 key) external view returns (uint256, bool) {
        return _cohortValue(key);
    }

    function setCutoffSchedule(uint48 nextCutoff, uint48 period) external {
        _setCutoffSchedule(nextCutoff, period);
    }

    function _cutoffPriceData() internal view override returns (uint256, uint48) {
        return (price, priceUpdatedAt);
    }

    function _cutoffToAssets(uint256 amount, uint256 rate) internal pure override returns (uint256) {
        return amount * rate / 1e18;
    }
}

contract CutoffPricerTest is Test {
    uint48 internal constant CUTOFF = 1_780_000_000;
    uint48 internal constant PERIOD = 30 days;
    uint48 internal constant VALUATION_DELAY = 5 days;
    uint48 internal constant SETTLEMENT_DURATION = 45 days;

    CutoffPricerHarness internal pricer;

    function setUp() public {
        vm.warp(CUTOFF - 10 days);
        pricer = new CutoffPricerHarness(CUTOFF, PERIOD, VALUATION_DELAY, SETTLEMENT_DURATION);
        pricer.setPriceData(1e18, uint48(block.timestamp));
    }

    function testRegisterAssignsCurrentCutoff() public {
        pricer.registerPending(1, 100e18);
        (uint128 amount,, uint48 cutoffTimestamp) = pricer.pendingCohorts(1);
        assertEq(amount, 100e18);
        assertEq(cutoffTimestamp, CUTOFF);
    }

    function testRegisterRollsCutoffForward() public {
        vm.warp(CUTOFF + 1);
        pricer.registerPending(1, 100e18);
        (,, uint48 cutoffTimestamp) = pricer.pendingCohorts(1);
        assertEq(cutoffTimestamp, CUTOFF + PERIOD);
        assertEq(pricer.cutoff(), CUTOFF + PERIOD);

        // exactly at a cutoff joins that cohort
        vm.warp(CUTOFF + PERIOD);
        pricer.registerPending(2, 1e18);
        (,, uint48 cutoffTimestamp2) = pricer.pendingCohorts(2);
        assertEq(cutoffTimestamp2, CUTOFF + PERIOD);

        // multiple periods elapsed
        vm.warp(CUTOFF + 3 * uint256(PERIOD) + 1);
        pricer.registerPending(3, 1e18);
        (,, uint48 cutoffTimestamp3) = pricer.pendingCohorts(3);
        assertEq(cutoffTimestamp3, CUTOFF + 4 * uint256(PERIOD));
    }

    function testRollingModeUsesRegistrationTime() public {
        CutoffPricerHarness rolling = new CutoffPricerHarness(0, 0, 0, 3 days);
        rolling.setPriceData(1e18, uint48(block.timestamp));
        rolling.registerPending(1, 100e18);
        (,, uint48 cutoffTimestamp) = rolling.pendingCohorts(1);
        assertEq(cutoffTimestamp, uint48(block.timestamp));
    }

    function testPendingValueLiveBeforeFreeze() public {
        pricer.registerPending(1, 100e18);
        pricer.setPriceData(1.1e18, uint48(block.timestamp));
        assertEq(pricer.pendingValue(1), 110e18);
    }

    function testFreezeRequiresPricingTimeAndFreshOracle() public {
        pricer.registerPending(1, 100e18);
        uint48 pricingTime = CUTOFF + VALUATION_DELAY;

        // before pricing time: no freeze
        pricer.tryFreezePending(1);
        (, uint128 frozenRate,) = pricer.pendingCohorts(1);
        assertEq(frozenRate, 0);

        // after pricing time but oracle stale (updatedAt < pricingTime): no freeze
        vm.warp(pricingTime + 1);
        pricer.setPriceData(1.2e18, pricingTime - 1);
        pricer.tryFreezePending(1);
        (, frozenRate,) = pricer.pendingCohorts(1);
        assertEq(frozenRate, 0);
        assertEq(pricer.pendingValue(1), 120e18); // still live

        // fresh oracle print: freeze at that rate
        pricer.setPriceData(1.25e18, pricingTime + 1);
        pricer.tryFreezePending(1);
        (, frozenRate,) = pricer.pendingCohorts(1);
        assertEq(frozenRate, 1.25e18);

        // later price changes no longer affect value
        pricer.setPriceData(2e18, uint48(block.timestamp));
        assertEq(pricer.pendingValue(1), 125e18);
    }

    function testWriteOffAfterSettlementDuration() public {
        pricer.registerPending(1, 100e18);
        vm.warp(CUTOFF + VALUATION_DELAY + SETTLEMENT_DURATION - 1);
        pricer.setPriceData(1e18, uint48(block.timestamp));
        assertGt(pricer.pendingValue(1), 0);
        vm.warp(CUTOFF + VALUATION_DELAY + SETTLEMENT_DURATION);
        assertEq(pricer.pendingValue(1), 0);
    }

    function testClearPending() public {
        pricer.registerPending(1, 100e18);
        pricer.clearPending(1);
        assertEq(pricer.pendingValue(1), 0);
        (uint128 amount,,) = pricer.pendingCohorts(1);
        assertEq(amount, 0);
    }

    function testSetCutoffScheduleValidation() public {
        vm.expectRevert(ICutoffPricer.InvalidCutoffSchedule.selector);
        pricer.setCutoffSchedule(uint48(block.timestamp + 1), 0);
        vm.expectRevert(ICutoffPricer.InvalidCutoffSchedule.selector);
        pricer.setCutoffSchedule(0, PERIOD);

        pricer.setCutoffSchedule(CUTOFF + 7 days, 91 days);
        assertEq(pricer.cutoff(), CUTOFF + 7 days);
        assertEq(pricer.cutoffPeriod(), 91 days);
    }

    function testZeroLivePriceReverts() public {
        pricer.registerPending(1, 100e18);
        pricer.setPriceData(0, uint48(block.timestamp));
        vm.expectRevert(ICutoffPricer.InvalidCutoffPrice.selector);
        pricer.pendingValue(1);
    }

    function testFrozenEntryIsWrittenOffAfterSettlementDuration() public {
        pricer.registerPending(1, 100e18);
        uint48 pricingTime = CUTOFF + VALUATION_DELAY;

        vm.warp(pricingTime + 1);
        pricer.setPriceData(1.3e18, pricingTime + 1);
        pricer.tryFreezePending(1);
        (, uint128 frozenRate,) = pricer.pendingCohorts(1);
        assertEq(frozenRate, 1.3e18);

        vm.warp(pricingTime + SETTLEMENT_DURATION);
        assertEq(pricer.pendingValue(1), 0);
    }

    function testScheduleChangeKeepsExistingEntries() public {
        pricer.registerPending(1, 100e18);
        (,, uint48 cutoffTimestampBefore) = pricer.pendingCohorts(1);
        assertEq(cutoffTimestampBefore, CUTOFF);

        pricer.setCutoffSchedule(CUTOFF + 100 days, 91 days);

        (,, uint48 cutoffTimestampAfter) = pricer.pendingCohorts(1);
        assertEq(cutoffTimestampAfter, CUTOFF);

        // entry still prices and freezes per the original cohort
        uint48 pricingTime = CUTOFF + VALUATION_DELAY;
        vm.warp(pricingTime + 1);
        pricer.setPriceData(1.4e18, pricingTime);
        pricer.tryFreezePending(1);
        (, uint128 frozenRate,) = pricer.pendingCohorts(1);
        assertEq(frozenRate, 1.4e18);
        assertEq(pricer.pendingValue(1), 140e18);
    }

    function testFrozenEntrySurvivesZeroOracle() public {
        pricer.registerPending(1, 100e18);
        uint48 pricingTime = CUTOFF + VALUATION_DELAY;

        vm.warp(pricingTime + 1);
        pricer.setPriceData(1.5e18, pricingTime + 1);
        pricer.tryFreezePending(1);

        pricer.setPriceData(0, uint48(block.timestamp));
        assertEq(pricer.pendingValue(1), 150e18);
    }

    function testZeroPriceSkipsFreeze() public {
        pricer.registerPending(1, 100e18);
        uint48 pricingTime = CUTOFF + VALUATION_DELAY;

        vm.warp(pricingTime + 1);
        pricer.setPriceData(0, pricingTime + 1);
        pricer.tryFreezePending(1);
        (, uint128 frozenRate,) = pricer.pendingCohorts(1);
        assertEq(frozenRate, 0);

        // entry still values live once a nonzero price is restored
        pricer.setPriceData(1.6e18, uint48(block.timestamp));
        assertEq(pricer.pendingValue(1), 160e18);
    }

    function testRollingModeFreezesAtFirstPrintAfterRequest() public {
        CutoffPricerHarness rolling = new CutoffPricerHarness(0, 0, 0, 3 days);
        uint48 registrationTime = uint48(block.timestamp);

        rolling.registerPending(1, 100e18);
        (,, uint48 cutoffTimestamp) = rolling.pendingCohorts(1);
        assertEq(cutoffTimestamp, registrationTime);

        // stale oracle print (updatedAt < registration time): no freeze
        rolling.setPriceData(1.1e18, registrationTime - 1);
        rolling.tryFreezePending(1);
        (, uint128 frozenRate,) = rolling.pendingCohorts(1);
        assertEq(frozenRate, 0);

        // first print at/after registration: frozen at that rate
        rolling.setPriceData(1.2e18, registrationTime);
        rolling.tryFreezePending(1);
        (, frozenRate,) = rolling.pendingCohorts(1);
        assertEq(frozenRate, 1.2e18);

        // later price moves no longer affect value
        rolling.setPriceData(2e18, uint48(block.timestamp));
        assertEq(rolling.pendingValue(1), 120e18);
    }

    function testFreezeBoundaryExactlyAtPricingTime() public {
        pricer.registerPending(1, 100e18);
        uint48 pricingTime = CUTOFF + VALUATION_DELAY;

        vm.warp(pricingTime);
        pricer.setPriceData(1.7e18, pricingTime);
        pricer.tryFreezePending(1);
        (, uint128 frozenRate,) = pricer.pendingCohorts(1);
        assertEq(frozenRate, 1.7e18);
    }

    function testFreezeSkippedAfterWriteOff() public {
        pricer.registerPending(1, 100e18);
        uint48 pricingTime = CUTOFF + VALUATION_DELAY;

        vm.warp(pricingTime + SETTLEMENT_DURATION);
        pricer.setPriceData(1.8e18, uint48(block.timestamp));
        pricer.tryFreezePending(1);
        (, uint128 frozenRate,) = pricer.pendingCohorts(1);
        assertEq(frozenRate, 0);
        assertEq(pricer.pendingValue(1), 0);
    }

    function testCohortValueReportsWriteOffWithoutZeroing() public {
        pricer.registerPending(1, 100e18);
        uint48 pricingTime = CUTOFF + VALUATION_DELAY;

        vm.warp(pricingTime + 1);
        pricer.setPriceData(1.5e18, pricingTime + 1);
        pricer.tryFreezePending(1);
        (, uint128 frozenRate,) = pricer.pendingCohorts(1);
        assertEq(frozenRate, 1.5e18);

        vm.warp(pricingTime + SETTLEMENT_DURATION);
        (uint256 value, bool writtenOff) = pricer.cohortValue(1);
        assertEq(value, 150e18);
        assertTrue(writtenOff);
        assertEq(pricer.pendingValue(1), 0);
    }

    function testCohortValueEmptyEntry() public view {
        (uint256 value, bool writtenOff) = pricer.cohortValue(42);
        assertEq(value, 0);
        assertFalse(writtenOff);
    }

    function testFreezeEmitsEvent() public {
        pricer.registerPending(1, 100e18);
        uint48 pricingTime = CUTOFF + VALUATION_DELAY;

        vm.warp(pricingTime + 1);
        pricer.setPriceData(1.9e18, pricingTime + 1);

        vm.expectEmit(true, false, false, true, address(pricer));
        emit ICutoffPricer.FreezePendingCohort(1, 1.9e18);
        pricer.tryFreezePending(1);
    }
}
