# Cutoff-Based Redemptions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the approved design in `docs/superpowers/specs/2026-06-11-cutoff-redemptions-design.md`: a `CutoffPricer` cohort-valuation mixin, a unified `SettlementAccount` family replacing the near-identical Securitize/Superstate/DigiFT accounts (with the ACRED burn→transfer correctness fix), a `MidasCutoffAccount` for mGLOBAL, plus the Makina quote cap, Centrifuge claimable precision, and oracle `getPriceData()` extensions.

**Architecture:** `CutoffPricer` is a standalone abstract mixin (no `Account` inheritance → no diamonds) holding the cutoff schedule and per-request `{amount, frozenRate, cutoff}` registry; hosts wire three small hooks. `SettlementAccount is CooldownAccount, CutoffPricer` owns sub-account orchestration; issuer contracts only override `_createSubAccount()` and the sub-account's `_executeRedemption()`. Rolling issuers use the degenerate schedule (cutoff 0 ⇒ cohort = request time).

**Tech Stack:** Solidity 0.8.x (solc 0.8.35, evm osaka), Foundry (`forge build`, `forge test`), OpenZeppelin. Build: `forge build`. Unit tests: `forge test --no-match-path "*Mainnet*" -vv` (mainnet-fork tests need `ETH_RPC_URL`).

**Conventions:** match repo style exactly — section banners (`/* IMMUTABLES */`, `/* STATE VARIABLES */`, `/* CONSTRUCTOR */`, `/* VIEW FUNCTIONS */`, `/* PUBLIC FUNCTIONS */`, `/* INTERNAL FUNCTIONS */`, `/* INITIALIZATION */`), `/// @inheritdoc` on implementations, NatSpec in interfaces, errors/events declared in interfaces, BUSL-1.1 + `// Copyright (c) 2026 Symbiotic` header for contracts, MIT for interfaces. Run `forge fmt` before each commit.

---

## Execution order & parallelism

- Stage A (independent, parallelizable): Task 1 (oracles), Task 2 (CutoffPricer), Task 6 (Makina), Task 7 (AsyncRedeem/Centrifuge)
- Stage B (needs Task 2): Task 3 (SettlementAccount)
- Stage C (needs Stage B; Tasks 4a+4b share `ProviderAccounts.t.sol` → one worker): Task 4 (Superstate+Securitize), Task 5 (DigiFT), Task 8 (MidasCutoff — needs Tasks 1+2 only, can run in Stage C)
- Stage D: Task 9 (mainnet-fork spec tests), Task 10 (full verification)

---

### Task 1: `IPriceDataOracle` + `getPriceData()` on MidasOracle and ChainlinkOracle

**Files:**
- Create: `src/interfaces/adapters/ll-adapter/IPriceDataOracle.sol`
- Modify: `src/interfaces/adapters/ll-adapter/midas/IMidasOracle.sol` (add `aggregator()` to `IMidasDataFeed`; `IMidasOracle is IPriceDataOracle`)
- Modify: `src/interfaces/adapters/ll-adapter/oracles/IChainlinkOracle.sol` (`IChainlinkOracle is IPriceDataOracle`)
- Modify: `src/contracts/adapters/ll-adapter/oracles/MidasOracle.sol`
- Modify: `src/contracts/adapters/ll-adapter/oracles/ChainlinkOracle.sol`
- Test: create `test/adapters/ll-adapter/PriceDataOracles.t.sol`

- [ ] **Step 1: Write the failing test**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ChainlinkOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/ChainlinkOracle.sol";
import {MidasOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/MidasOracle.sol";

contract MockAggregatorV3 {
    int256 public answer;
    uint256 public updatedAt;
    uint8 public immutable decimals;

    constructor(uint8 decimals_) {
        decimals = decimals_;
    }

    function setRound(int256 answer_, uint256 updatedAt_) external {
        answer = answer_;
        updatedAt = updatedAt_;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, answer, updatedAt, updatedAt, 1);
    }

    function getRoundData(uint80) external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, answer, updatedAt, updatedAt, 1);
    }
}

contract MockMidasDataFeed {
    address public aggregator;
    uint256 internal _answer;

    constructor(address aggregator_) {
        aggregator = aggregator_;
    }

    function setAnswer(uint256 answer_) external {
        _answer = answer_;
    }

    function getDataInBase18() external view returns (uint256) {
        return _answer;
    }
}

contract PriceDataOraclesTest is Test {
    function testMidasOracleReturnsPriceAndAggregatorUpdatedAt() public {
        MockAggregatorV3 aggregator = new MockAggregatorV3(8);
        MockMidasDataFeed dataFeed = new MockMidasDataFeed(address(aggregator));
        dataFeed.setAnswer(0.93e18);
        aggregator.setRound(0.93e8, 1_750_000_000);

        MidasOracle oracle = new MidasOracle(address(dataFeed));
        (uint256 price, uint48 updatedAt) = oracle.getPriceData();
        assertEq(price, 0.93e18);
        assertEq(updatedAt, 1_750_000_000);
    }

    function testChainlinkOracleReturnsOldestUpdatedAtOfTwoAggregators() public {
        MockAggregatorV3 aggregator0 = new MockAggregatorV3(8);
        MockAggregatorV3 aggregator1 = new MockAggregatorV3(8);
        vm.warp(2_000_000_000);
        aggregator0.setRound(1e8, 1_999_999_000);
        aggregator1.setRound(2e8, 1_999_998_000);

        ChainlinkOracle oracle =
            new ChainlinkOracle([address(aggregator0), address(aggregator1)], [uint48(1 days), uint48(1 days)]);
        (uint256 price, uint48 updatedAt) = oracle.getPriceData();
        assertEq(price, 2e18);
        assertEq(updatedAt, 1_999_998_000);
    }

    function testChainlinkOracleSingleAggregatorUpdatedAt() public {
        MockAggregatorV3 aggregator0 = new MockAggregatorV3(8);
        vm.warp(2_000_000_000);
        aggregator0.setRound(1e8, 1_999_999_123);

        ChainlinkOracle oracle = new ChainlinkOracle([address(aggregator0), address(0)], [uint48(1 days), uint48(0)]);
        (, uint48 updatedAt) = oracle.getPriceData();
        assertEq(updatedAt, 1_999_999_123);
    }
}
```

- [ ] **Step 2: Run to verify failure** — `forge test --match-path "test/adapters/ll-adapter/PriceDataOracles.t.sol" -vv`. Expected: compilation failure (`getPriceData` undefined).

- [ ] **Step 3: Implement**

`src/interfaces/adapters/ll-adapter/IPriceDataOracle.sol` (new):

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IOracle} from "./IOracle.sol";

/**
 * @title IPriceDataOracle
 * @notice Interface for liquidity lane token oracles exposing the price update timestamp.
 */
interface IPriceDataOracle is IOracle {
    /* FUNCTIONS */

    /**
     * @notice Returns the token price and its last update timestamp.
     * @return price Token price in 1e18 precision against a shared quote.
     * @return updatedAt Timestamp of the last price update.
     */
    function getPriceData() external view returns (uint256 price, uint48 updatedAt);
}
```

`IMidasOracle.sol`: add to `IMidasDataFeed`:

```solidity
    /**
     * @notice Returns the underlying Chainlink-compatible aggregator.
     * @return aggregator The aggregator address.
     */
    function aggregator() external view returns (address aggregator);
```

and change `interface IMidasOracle is IOracle` → `interface IMidasOracle is IPriceDataOracle` (import `IPriceDataOracle` from `../IPriceDataOracle.sol`; keep the `IOracle` import only if still referenced).

`MidasOracle.sol`: import `AggregatorV3Interface` from `./libraries/ChainlinkPriceFeed.sol` and `IPriceDataOracle`; add:

```solidity
    /// @inheritdoc IPriceDataOracle
    function getPriceData() public view returns (uint256 price, uint48 updatedAt) {
        price = getPrice();
        (,,, uint256 timestamp,) =
            AggregatorV3Interface(IMidasDataFeed(DATA_FEED).aggregator()).latestRoundData();
        updatedAt = uint48(timestamp);
    }
```

`IChainlinkOracle.sol`: change base `IOracle` → `IPriceDataOracle` (adjust imports).

`ChainlinkOracle.sol`: import `AggregatorV3Interface` from `./libraries/ChainlinkPriceFeed.sol` and add:

```solidity
    /// @inheritdoc IPriceDataOracle
    function getPriceData() public view returns (uint256 price, uint48 updatedAt) {
        price = getPrice();
        (,,, uint256 timestamp,) = AggregatorV3Interface(AGGREGATOR_0).latestRoundData();
        updatedAt = uint48(timestamp);
        if (AGGREGATOR_1 != address(0)) {
            (,,, uint256 timestamp1,) = AggregatorV3Interface(AGGREGATOR_1).latestRoundData();
            if (timestamp1 < updatedAt) {
                updatedAt = uint48(timestamp1);
            }
        }
    }
```

Note: `ChainlinkOracle.getPrice()` may return 0 on staleness (lib semantics) — `getPriceData` intentionally mirrors `getPrice()` for the price leg. Check the actual `IChainlinkOracle`/`IMidasOracle` files for `@inheritdoc` targets and existing imports before editing.

- [ ] **Step 4: Run tests** — same command. Expected: 3 PASS. Also `forge build` clean.
- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: price-data oracles with update timestamps"`

---

### Task 2: `CutoffPricer` mixin + `ICutoffPricer` + unit tests

**Files:**
- Create: `src/interfaces/adapters/ll-adapter/ICutoffPricer.sol`
- Create: `src/contracts/adapters/ll-adapter/common/CutoffPricer.sol`
- Test: create `test/adapters/ll-adapter/CutoffPricer.t.sol`

- [ ] **Step 1: Write the failing tests**

```solidity
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
}
```

- [ ] **Step 2: Run to verify failure** — `forge test --match-path "test/adapters/ll-adapter/CutoffPricer.t.sol"`. Expected: compile error (missing files).

- [ ] **Step 3: Implement**

`src/interfaces/adapters/ll-adapter/ICutoffPricer.sol` (new):

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title ICutoffPricer
 * @notice Interface for accounts pricing pending redemptions against issuer cutoff cohorts.
 */
interface ICutoffPricer {
    /* ERRORS */

    /**
     * @notice Raised when a cutoff schedule is partially zero.
     */
    error InvalidCutoffSchedule();

    /**
     * @notice Raised when the live cutoff price is zero.
     */
    error InvalidCutoffPrice();

    /* EVENTS */

    /**
     * @notice Emitted when the cutoff schedule is updated.
     * @param nextCutoff The next cutoff timestamp (0 for rolling mode).
     * @param period The cutoff period (0 for rolling mode).
     */
    event SetCutoffSchedule(uint48 nextCutoff, uint48 period);

    /**
     * @notice Emitted when a pending cohort's rate is frozen.
     * @param key The pending redemption key.
     * @param rate The frozen rate in 1e18 precision.
     */
    event FreezePendingCohort(uint256 indexed key, uint256 rate);

    /* STRUCTS */

    /**
     * @notice Pending redemption tracked against a cutoff cohort.
     * @param amount The token-to-redeem amount pending.
     * @param frozenRate The cohort rate captured at/after the pricing date (0 until frozen).
     * @param cutoffTimestamp The cohort cutoff timestamp assigned at registration.
     */
    struct PendingCohort {
        uint128 amount;
        uint128 frozenRate;
        uint48 cutoffTimestamp;
    }

    /* FUNCTIONS */

    /**
     * @notice Returns the delay between a cutoff and its cohort pricing date.
     * @return valuationDelay The valuation delay.
     */
    function VALUATION_DELAY() external view returns (uint48 valuationDelay);

    /**
     * @notice Returns how long after the pricing date pending value is counted.
     * @return settlementDuration The settlement duration.
     */
    function SETTLEMENT_DURATION() external view returns (uint48 settlementDuration);

    /**
     * @notice Returns the next cutoff timestamp (0 for rolling mode).
     * @return nextCutoff The next cutoff timestamp.
     */
    function cutoff() external view returns (uint48 nextCutoff);

    /**
     * @notice Returns the cutoff period (0 for rolling mode).
     * @return period The cutoff period.
     */
    function cutoffPeriod() external view returns (uint48 period);

    /**
     * @notice Returns a tracked pending cohort entry.
     * @param key The pending redemption key.
     * @return amount The token-to-redeem amount pending.
     * @return frozenRate The frozen cohort rate (0 until frozen).
     * @return cutoffTimestamp The assigned cohort cutoff timestamp.
     */
    function pendingCohorts(uint256 key)
        external
        view
        returns (uint128 amount, uint128 frozenRate, uint48 cutoffTimestamp);
}
```

`src/contracts/adapters/ll-adapter/common/CutoffPricer.sol` (new):

```solidity
// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {ICutoffPricer} from "../../../../interfaces/adapters/ll-adapter/ICutoffPricer.sol";

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @title CutoffPricer
/// @notice Mixin pricing pending redemptions against issuer cutoff cohorts.
/// @dev Pending value tracks the live oracle until the cohort pricing date, then freezes at the first
///      oracle price published at/after that date, and is written off after the settlement duration.
///      A zero schedule (rolling mode) assigns each registration its own cohort at registration time.
abstract contract CutoffPricer is ICutoffPricer {
    using SafeCast for uint256;

    /* IMMUTABLES */

    /// @inheritdoc ICutoffPricer
    uint48 public immutable VALUATION_DELAY;
    /// @inheritdoc ICutoffPricer
    uint48 public immutable SETTLEMENT_DURATION;

    /// @dev Initial next-cutoff timestamp applied on initialization (0 for rolling mode).
    uint48 internal immutable INITIAL_CUTOFF;
    /// @dev Initial cutoff period applied on initialization (0 for rolling mode).
    uint48 internal immutable INITIAL_CUTOFF_PERIOD;

    /* STATE VARIABLES */

    /// @inheritdoc ICutoffPricer
    uint48 public cutoff;
    /// @inheritdoc ICutoffPricer
    uint48 public cutoffPeriod;

    /// @inheritdoc ICutoffPricer
    mapping(uint256 key => PendingCohort pendingCohort) public pendingCohorts;

    /* CONSTRUCTOR */

    /// @notice Creates the cutoff pricer.
    constructor(uint48 initialCutoff, uint48 initialCutoffPeriod, uint48 valuationDelay, uint48 settlementDuration) {
        if ((initialCutoff == 0) != (initialCutoffPeriod == 0)) {
            revert InvalidCutoffSchedule();
        }

        INITIAL_CUTOFF = initialCutoff;
        INITIAL_CUTOFF_PERIOD = initialCutoffPeriod;
        VALUATION_DELAY = valuationDelay;
        SETTLEMENT_DURATION = settlementDuration;
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Applies the constructor schedule to state. Call once from the host's initializer.
    function __CutoffPricer_init() internal {
        cutoff = INITIAL_CUTOFF;
        cutoffPeriod = INITIAL_CUTOFF_PERIOD;
    }

    /// @dev Updates the cutoff schedule. Hosts expose this behind their owner check.
    function _setCutoffSchedule(uint48 nextCutoff, uint48 period) internal {
        if ((nextCutoff == 0) != (period == 0)) {
            revert InvalidCutoffSchedule();
        }

        cutoff = nextCutoff;
        cutoffPeriod = period;

        emit SetCutoffSchedule(nextCutoff, period);
    }

    /// @dev Tracks a pending redemption under the current cohort.
    function _registerPending(uint256 key, uint256 amount) internal {
        pendingCohorts[key] =
            PendingCohort({amount: amount.toUint128(), frozenRate: 0, cutoffTimestamp: _rollCutoff()});
    }

    /// @dev Freezes the cohort rate once the pricing date passed and the oracle published at/after it.
    function _tryFreezePending(uint256 key) internal {
        PendingCohort storage pendingCohort = pendingCohorts[key];
        if (pendingCohort.amount == 0 || pendingCohort.frozenRate != 0) {
            return;
        }

        uint256 pricingTimestamp = pendingCohort.cutoffTimestamp + VALUATION_DELAY;
        if (block.timestamp < pricingTimestamp) {
            return;
        }

        (uint256 price, uint48 updatedAt) = _cutoffPriceData();
        if (price != 0 && updatedAt >= pricingTimestamp) {
            pendingCohort.frozenRate = price.toUint128();

            emit FreezePendingCohort(key, price);
        }
    }

    /// @dev Stops tracking a pending redemption.
    function _clearPending(uint256 key) internal {
        delete pendingCohorts[key];
    }

    /// @dev Returns the pending redemption value: live until frozen, frozen until written off.
    function _pendingValue(uint256 key) internal view returns (uint256 assets) {
        PendingCohort storage pendingCohort = pendingCohorts[key];
        uint256 amount = pendingCohort.amount;
        if (amount == 0) {
            return 0;
        }

        uint256 pricingTimestamp = pendingCohort.cutoffTimestamp + VALUATION_DELAY;
        if (block.timestamp >= pricingTimestamp + SETTLEMENT_DURATION) {
            return 0;
        }

        uint256 rate = pendingCohort.frozenRate;
        if (rate == 0) {
            (rate,) = _cutoffPriceData();
            if (rate == 0) {
                revert InvalidCutoffPrice();
            }
        }
        return _cutoffToAssets(amount, rate);
    }

    /// @dev Rolls the stored cutoff to the first cutoff at/after the current time and returns it.
    function _rollCutoff() internal returns (uint48 currentCutoff) {
        currentCutoff = cutoff;
        if (currentCutoff == 0) {
            return uint48(block.timestamp);
        }

        if (block.timestamp > currentCutoff) {
            uint256 period = cutoffPeriod;
            currentCutoff =
                (currentCutoff + ((block.timestamp - currentCutoff - 1) / period + 1) * period).toUint48();
            cutoff = currentCutoff;
        }
    }

    /// @dev Returns the live oracle price and its last update timestamp.
    function _cutoffPriceData() internal view virtual returns (uint256 price, uint48 updatedAt);

    /// @dev Converts a token-to-redeem amount to vault assets at a rate.
    function _cutoffToAssets(uint256 amount, uint256 rate) internal view virtual returns (uint256 assets);
}
```

- [ ] **Step 4: Run tests** — `forge test --match-path "test/adapters/ll-adapter/CutoffPricer.t.sol" -vv`. Expected: all PASS.
- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: cutoff cohort pricer mixin"`

---

### Task 3: `SettlementAccount` + `SettlementSubAccount` + interfaces

**Files:**
- Create: `src/interfaces/adapters/ll-adapter/ISettlementAccount.sol`
- Create: `src/interfaces/adapters/ll-adapter/ISettlementSubAccount.sol`
- Create: `src/contracts/adapters/ll-adapter/common/SettlementAccount.sol`

This task is compile-only (behavior is exercised through the issuer rewrites in Tasks 4–5, which carry the tests).

- [ ] **Step 1: Write interfaces**

`src/interfaces/adapters/ll-adapter/ISettlementAccount.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ICooldownAccount} from "./ICooldownAccount.sol";
import {ICutoffPricer} from "./ICutoffPricer.sol";

/**
 * @title ISettlementAccount
 * @notice Interface for liquidity lane accounts settling redemptions through request-holder subaccounts.
 */
interface ISettlementAccount is ICooldownAccount, ICutoffPricer {
    /* FUNCTIONS */

    /**
     * @notice Returns a redemption-request subaccount by index.
     * @param index The subaccount index.
     * @return subAccount The subaccount address.
     */
    function subAccounts(uint256 index) external view returns (address subAccount);

    /**
     * @notice Updates the cutoff schedule. Only callable by the owner.
     * @param nextCutoff The next cutoff timestamp (0 for rolling mode).
     * @param period The cutoff period (0 for rolling mode).
     */
    function setCutoffSchedule(uint48 nextCutoff, uint48 period) external;
}
```

`src/interfaces/adapters/ll-adapter/ISettlementSubAccount.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title ISettlementSubAccount
 * @notice Interface for request-holder subaccounts of one issuer redemption.
 */
interface ISettlementSubAccount {
    /* ERRORS */

    /**
     * @notice Raised when a caller is not the parent account.
     */
    error NotAccount();

    /* FUNCTIONS */

    /**
     * @notice Requests redemption of held tokens through the issuer.
     */
    function requestRedeem() external;

    /**
     * @notice Sweeps received settlement assets and returned tokens to the parent account.
     */
    function sync() external;

    /**
     * @notice Returns whether settlement assets have been received.
     * @return status True if the settlement batch arrived.
     */
    function isSettled() external view returns (bool status);
}
```

- [ ] **Step 2: Write `src/contracts/adapters/ll-adapter/common/SettlementAccount.sol`**

```solidity
// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {CooldownAccount} from "./CooldownAccount.sol";
import {CutoffPricer} from "./CutoffPricer.sol";

import {IPriceDataOracle} from "../../../../interfaces/adapters/ll-adapter/IPriceDataOracle.sol";
import {ISettlementAccount} from "../../../../interfaces/adapters/ll-adapter/ISettlementAccount.sol";
import {ISettlementSubAccount} from "../../../../interfaces/adapters/ll-adapter/ISettlementSubAccount.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title SettlementAccount
/// @notice Base account settling redemptions through per-request subaccounts priced by cutoff cohorts.
abstract contract SettlementAccount is CooldownAccount, CutoffPricer, ISettlementAccount {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /* STATE VARIABLES */

    /// @inheritdoc ISettlementAccount
    address[] public subAccounts;

    /* CONSTRUCTOR */

    /// @notice Creates the settlement account implementation.
    constructor(
        address oracle,
        address factory,
        uint48 cooldown,
        address tokenToRedeem,
        uint48 initialCutoff,
        uint48 initialCutoffPeriod,
        uint48 valuationDelay,
        uint48 settlementDuration,
        address cowSwapSettlement
    )
        CooldownAccount(oracle, factory, cooldown, tokenToRedeem, cowSwapSettlement)
        CutoffPricer(initialCutoff, initialCutoffPeriod, valuationDelay, settlementDuration)
    {}

    /* PUBLIC FUNCTIONS (OWNER) */

    /// @inheritdoc ISettlementAccount
    function setCutoffSchedule(uint48 nextCutoff, uint48 period) public onlyOwner {
        _setCutoffSchedule(nextCutoff, period);
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Returns subaccount holdings plus any pending receivable not yet realized.
    function _totalAssets() internal view override returns (uint256 assets) {
        for (uint256 i; i < subAccounts.length; ++i) {
            address subAccount = subAccounts[i];

            uint256 holdings = IERC20(_asset).balanceOf(subAccount);
            uint256 tokenBalance = IERC20(TOKEN_TO_REDEEM).balanceOf(subAccount);
            if (tokenBalance > 0) {
                holdings += _tokenToRedeemToAssets(tokenBalance);
            }

            assets += holdings + _pendingValue(uint160(subAccount)).saturatingSub(holdings);
        }
    }

    /// @dev Freezes cohort rates, sweeps settled subaccounts, and clears them.
    function _finalizeRequests() internal override {
        for (uint256 i = subAccounts.length; i > 0; --i) {
            uint256 index = i - 1;
            address subAccount = subAccounts[index];

            _tryFreezePending(uint160(subAccount));

            ISettlementSubAccount(subAccount).sync();
            if (ISettlementSubAccount(subAccount).isSettled()) {
                _clearPending(uint160(subAccount));
                subAccounts[index] = subAccounts[subAccounts.length - 1];
                subAccounts.pop();
            }
        }
    }

    /// @dev Submits held token-to-redeem inventory through a new request-holder subaccount.
    function _requestRedeem() internal override {
        uint256 amount = IERC20(TOKEN_TO_REDEEM).balanceOf(address(this));
        address subAccount = _createSubAccount();

        subAccounts.push(subAccount);
        _registerPending(uint160(subAccount), amount);
        IERC20(TOKEN_TO_REDEEM).safeTransfer(subAccount, amount);
        ISettlementSubAccount(subAccount).requestRedeem();
    }

    /// @dev Deploys the issuer-specific request-holder subaccount.
    function _createSubAccount() internal virtual returns (address subAccount);

    /// @inheritdoc CutoffPricer
    function _cutoffPriceData() internal view override returns (uint256 price, uint48 updatedAt) {
        return IPriceDataOracle(ORACLE).getPriceData();
    }

    /// @inheritdoc CutoffPricer
    function _cutoffToAssets(uint256 amount, uint256 rate) internal view override returns (uint256 assets) {
        return _tokenToRedeemToAssets(amount, rate);
    }

    /* INITIALIZATION */

    /// @dev Initializes the account and applies the cutoff schedule.
    function _initialize(uint64 initialVersion, address initOwner, bytes memory data) internal virtual override {
        super._initialize(initialVersion, initOwner, data);
        __CutoffPricer_init();
    }
}

/// @title SettlementSubAccount
/// @notice Request-holder subaccount for one issuer redemption settlement.
abstract contract SettlementSubAccount is ISettlementSubAccount {
    using SafeERC20 for IERC20;

    /* IMMUTABLES */

    /// @dev Parent account that owns this subaccount.
    address internal immutable ACCOUNT;
    /// @dev Vault asset expected from settlement.
    address internal immutable ASSET;
    /// @dev Token submitted for redemption.
    address internal immutable TOKEN_TO_REDEEM;

    /* STATE VARIABLES */

    /// @dev Whether settlement assets have been received.
    bool internal _settled;

    /* CONSTRUCTOR */

    /// @notice Creates the request-holder subaccount.
    constructor(address asset, address account, address tokenToRedeem) {
        ASSET = asset;
        ACCOUNT = account;
        TOKEN_TO_REDEEM = tokenToRedeem;
    }

    /* PUBLIC FUNCTIONS */

    /// @inheritdoc ISettlementSubAccount
    function requestRedeem() external {
        if (msg.sender != ACCOUNT) {
            revert NotAccount();
        }

        _executeRedemption();
    }

    /// @inheritdoc ISettlementSubAccount
    function sync() external {
        if (msg.sender != ACCOUNT) {
            revert NotAccount();
        }

        uint256 assets = IERC20(ASSET).balanceOf(address(this));
        if (assets > 0) {
            _settled = true;
            IERC20(ASSET).safeTransfer(ACCOUNT, assets);
        }

        uint256 tokenBalance = IERC20(TOKEN_TO_REDEEM).balanceOf(address(this));
        if (tokenBalance > 0) {
            IERC20(TOKEN_TO_REDEEM).safeTransfer(ACCOUNT, tokenBalance);
        }
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc ISettlementSubAccount
    function isSettled() public view returns (bool status) {
        return _settled;
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Submits the held token balance to the issuer's redemption flow.
    function _executeRedemption() internal virtual;
}
```

Note on overrides: `CooldownAccount` declares `_finalizeRequests`/`_requestRedeem` as virtual without other bases declaring them, and `CutoffPricer` shares no ancestors with `Account`, so single-name `override` is sufficient everywhere. If the compiler asks for multi-base override specifiers on `_totalAssets`/`_initialize`, use `override(Account)` style as instructed by the error.

- [ ] **Step 3: Build** — `forge build`. Expected: clean (new contracts compile, nothing references them yet).
- [ ] **Step 4: Commit** — `git add -A && git commit -m "feat: settlement account family on cutoff pricer"`

---

### Task 4: Rewrite `SuperstateAccount` + `SecuritizeAccount`; update USCC/ACRED token files; update tests

**Files:**
- Rewrite: `src/contracts/adapters/ll-adapter/SuperstateAccount.sol`
- Rewrite: `src/contracts/adapters/ll-adapter/SecuritizeAccount.sol`
- Modify: `src/interfaces/adapters/ll-adapter/superstate/ISuperstateAccount.sol`
- Modify: `src/interfaces/adapters/ll-adapter/securitize/ISecuritizeAccount.sol`
- Delete: `src/interfaces/adapters/ll-adapter/superstate/ISuperstateSubAccount.sol`, `src/interfaces/adapters/ll-adapter/securitize/ISecuritizeSubAccount.sol`, `src/interfaces/adapters/ll-adapter/securitize/ISecuritizeToken.sol`
- Modify: `src/contracts/adapters/ll-adapter/tokens-to-redeem/USCC_Account.sol`, `ACRED_Account.sol`
- Modify: `test/adapters/ll-adapter/ProviderAccounts.t.sol` (and `AccountsBase.t.sol` if its mocks/helpers are shared)

- [ ] **Step 1: New `SuperstateAccount.sol`** (full file)

```solidity
// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {SettlementAccount, SettlementSubAccount} from "./common/SettlementAccount.sol";

import {ISuperstateAccount} from "../../../interfaces/adapters/ll-adapter/superstate/ISuperstateAccount.sol";
import {ISuperstateToken} from "../../../interfaces/adapters/ll-adapter/superstate/ISuperstateToken.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title SuperstateAccount
/// @notice Account for Superstate off-chain settlement redemptions.
contract SuperstateAccount is SettlementAccount, ISuperstateAccount {
    /* CONSTRUCTOR */

    /// @notice Creates the Superstate account implementation.
    constructor(
        address oracle,
        address factory,
        uint48 cooldown,
        address tokenToRedeem,
        uint48 settlementDuration,
        address cowSwapSettlement
    ) SettlementAccount(oracle, factory, cooldown, tokenToRedeem, 0, 0, 0, settlementDuration, cowSwapSettlement) {}

    /* INTERNAL FUNCTIONS */

    /// @dev Deploys a Superstate request-holder subaccount.
    function _createSubAccount() internal override returns (address subAccount) {
        return address(new SuperstateSubAccount(_asset, address(this), TOKEN_TO_REDEEM));
    }
}

/// @title SuperstateSubAccount
/// @notice Request-holder subaccount for one Superstate off-chain redemption.
contract SuperstateSubAccount is SettlementSubAccount {
    /* CONSTRUCTOR */

    /// @notice Creates the Superstate request-holder subaccount.
    constructor(address asset, address account, address tokenToRedeem)
        SettlementSubAccount(asset, account, tokenToRedeem)
    {}

    /* INTERNAL FUNCTIONS */

    /// @dev Burns held Superstate tokens for off-chain settlement.
    function _executeRedemption() internal override {
        ISuperstateToken(TOKEN_TO_REDEEM).offchainRedeem(IERC20(TOKEN_TO_REDEEM).balanceOf(address(this)));
    }
}
```

`ISuperstateAccount.sol` becomes:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ISettlementAccount} from "../ISettlementAccount.sol";

/**
 * @title ISuperstateAccount
 * @notice Interface for Superstate liquidity lane accounts.
 */
interface ISuperstateAccount is ISettlementAccount {}
```

- [ ] **Step 2: New `SecuritizeAccount.sol`** (full file — note: redemption notice is a TRANSFER to the redemption wallet, not a burn)

```solidity
// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {SettlementAccount, SettlementSubAccount} from "./common/SettlementAccount.sol";

import {ISecuritizeAccount} from "../../../interfaces/adapters/ll-adapter/securitize/ISecuritizeAccount.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title SecuritizeAccount
/// @notice Account for Securitize off-chain settlement redemptions with windowed repurchases.
/// @dev The redemption notice is an ERC-20 transfer to the issuer's redemption wallet; settlement
///      returns vault assets for the repurchased portion and re-mints any unfilled remainder to the
///      subaccount, which sweeps it back for re-tender in the next window.
contract SecuritizeAccount is SettlementAccount, ISecuritizeAccount {
    /* IMMUTABLES */

    /// @inheritdoc ISecuritizeAccount
    address public immutable REDEMPTION_WALLET;

    /* CONSTRUCTOR */

    /// @notice Creates the Securitize account implementation.
    constructor(
        address oracle,
        address factory,
        uint48 cooldown,
        address tokenToRedeem,
        address redemptionWallet,
        uint48 initialCutoff,
        uint48 initialCutoffPeriod,
        uint48 valuationDelay,
        uint48 settlementDuration,
        address cowSwapSettlement
    )
        SettlementAccount(
            oracle,
            factory,
            cooldown,
            tokenToRedeem,
            initialCutoff,
            initialCutoffPeriod,
            valuationDelay,
            settlementDuration,
            cowSwapSettlement
        )
    {
        REDEMPTION_WALLET = redemptionWallet;
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Deploys a Securitize request-holder subaccount.
    function _createSubAccount() internal override returns (address subAccount) {
        return address(new SecuritizeSubAccount(_asset, address(this), TOKEN_TO_REDEEM, REDEMPTION_WALLET));
    }
}

/// @title SecuritizeSubAccount
/// @notice Request-holder subaccount for one Securitize off-chain redemption.
contract SecuritizeSubAccount is SettlementSubAccount {
    using SafeERC20 for IERC20;

    /* IMMUTABLES */

    /// @dev Securitize redemption wallet receiving the redemption notice transfer.
    address internal immutable REDEMPTION_WALLET;

    /* CONSTRUCTOR */

    /// @notice Creates the Securitize request-holder subaccount.
    constructor(address asset, address account, address tokenToRedeem, address redemptionWallet)
        SettlementSubAccount(asset, account, tokenToRedeem)
    {
        REDEMPTION_WALLET = redemptionWallet;
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Transfers held Securitize tokens to the redemption wallet as the redemption notice.
    function _executeRedemption() internal override {
        IERC20(TOKEN_TO_REDEEM).safeTransfer(REDEMPTION_WALLET, IERC20(TOKEN_TO_REDEEM).balanceOf(address(this)));
    }
}
```

`ISecuritizeAccount.sol` becomes:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ISettlementAccount} from "../ISettlementAccount.sol";

/**
 * @title ISecuritizeAccount
 * @notice Interface for Securitize liquidity lane accounts.
 */
interface ISecuritizeAccount is ISettlementAccount {
    /* FUNCTIONS */

    /**
     * @notice Returns the Securitize redemption wallet receiving redemption notices.
     * @return redemptionWallet The redemption wallet address.
     */
    function REDEMPTION_WALLET() external view returns (address redemptionWallet);
}
```

Delete `ISuperstateSubAccount.sol`, `ISecuritizeSubAccount.sol`, `ISecuritizeToken.sol` and remove all imports of them (grep: `grep -rn "ISecuritizeSubAccount\|ISuperstateSubAccount\|ISecuritizeToken" src/ test/ script/`).

- [ ] **Step 3: Update token files**

`USCC_Account.sol` (rename the duration constant; same 3-day value):

```solidity
// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";
import {SuperstateAccount} from "../SuperstateAccount.sol";

contract USCC_Account is SuperstateAccount {
    address internal constant TOKEN_ADDRESS = 0x14d60E7FDC0D71d8611742720E4C50E7a974020c;
    uint48 internal constant TOKEN_COOLDOWN = 12 hours;
    uint48 internal constant TOKEN_SETTLEMENT_DURATION = 3 days;

    constructor(address oracle, address factory, address cowSwapSettlement)
        SuperstateAccount(oracle, factory, TOKEN_COOLDOWN, TOKEN_ADDRESS, TOKEN_SETTLEMENT_DURATION, cowSwapSettlement)
    {}
}

contract USCC_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}
```

`ACRED_Account.sol` (quarterly schedule; `1785456000` = 2026-07-31 00:00:00 UTC):

```solidity
// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";
import {SecuritizeAccount} from "../SecuritizeAccount.sol";

contract ACRED_Account is SecuritizeAccount {
    address internal constant TOKEN_ADDRESS = 0x17418038ecF73BA4026c4f428547BF099706F27B;
    address internal constant REDEMPTION_WALLET_ADDRESS = 0xbb543C77436645C8b95B64eEc39E3C0d48D4842b;
    uint48 internal constant TOKEN_COOLDOWN = 9 days;
    /// @dev 2026-07-31 00:00:00 UTC feeder repurchase deadline; owner-maintained thereafter.
    uint48 internal constant INITIAL_CUTOFF = 1_785_456_000;
    uint48 internal constant INITIAL_CUTOFF_PERIOD = 91 days;
    uint48 internal constant TOKEN_VALUATION_DELAY = 5 days;
    uint48 internal constant TOKEN_SETTLEMENT_DURATION = 30 days;

    constructor(address oracle, address factory, address cowSwapSettlement)
        SecuritizeAccount(
            oracle,
            factory,
            TOKEN_COOLDOWN,
            TOKEN_ADDRESS,
            REDEMPTION_WALLET_ADDRESS,
            INITIAL_CUTOFF,
            INITIAL_CUTOFF_PERIOD,
            TOKEN_VALUATION_DELAY,
            TOKEN_SETTLEMENT_DURATION,
            cowSwapSettlement
        )
    {}
}

contract ACRED_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}
```

- [ ] **Step 4: Update `ProviderAccounts.t.sol` (and shared mocks)**

Read the existing file first. Required changes:
1. A reusable `MockPriceDataOracle` (add next to the existing `MockOracle` in `AccountsBase.t.sol`):

```solidity
contract MockPriceDataOracle {
    uint256 public price;
    uint48 public updatedAt;

    constructor(uint256 price_) {
        price = price_;
        updatedAt = uint48(block.timestamp);
    }

    function setPriceData(uint256 price_, uint48 updatedAt_) external {
        price = price_;
        updatedAt = updatedAt_;
    }

    function getPrice() external view returns (uint256) {
        return price;
    }

    function getPriceData() external view returns (uint256, uint48) {
        return (price, updatedAt);
    }
}
```

2. Superstate tests: replace the old construction (`PENDING_ASSETS_DURATION` arg position is unchanged — the constructor keeps 6 args with the same order, the 5th is now `settlementDuration`) and pass a `MockPriceDataOracle`. Keep `MockSuperstateToken.offchainRedeem` (burn-style) mock. Behavioral assertions to keep/adapt:
   - after `sync()` with a token balance: a subaccount exists, tokens were burned via `offchainRedeem`, `totalAssets()` equals the oracle value of the tendered amount (live pricing; with the mock oracle's `updatedAt == block.timestamp` at request time the value freezes on the next `sync()` — assert value stays at the frozen rate after a subsequent oracle price change followed by `sync()`).
   - settlement: deal USDC to the subaccount, `sync()` → USDC swept to the account, subaccount removed (`subAccounts(0)` reverts), `totalAssets()` = swept balance.
   - write-off: with no settlement, `vm.warp(request + 3 days)` → `totalAssets()` drops the pending value to 0.
3. Securitize tests: replace burn-mock with transfer semantics:
   - `testSecuritizeTransfersToRedemptionWalletAndSweepsSettlement`: token balance → `sync()` → tokens now owned by the redemption wallet address (plain ERC-20 transfer; assert `acred.balanceOf(redemptionWallet) == amount`), pending valued live.
   - `testSecuritizeSweepsPartialFillRemint`: simulate quarterly settlement — deal USDC (35% of expected) to the subaccount AND mint ACRED (65% of tendered) back to the subaccount; `sync()` → both swept to the parent account, subaccount cleared, `totalAssets()` ≈ USDC + oracle value of re-minted ACRED; a later `sync()` past cooldown re-tenders the re-minted tokens into a new subaccount.
   - `testSecuritizeFreezesCohortRateAfterPricingDate`: deploy with `initialCutoff = now + 10 days`, `period = 91 days`, `valuationDelay = 5 days`, `settlementDuration = 30 days` (use a direct `SecuritizeAccount` deployment via factory, mirroring `_deploySecuritize`); request now (cohort = cutoff); warp to `cutoff + 5 days + 1`; set oracle `(1.2e18, cutoff + 5 days + 1)`; `sync()`; then set oracle price to `2e18` and assert `totalAssets()` still uses `1.2e18`; warp past `cutoff + 5 days + 30 days` and assert pending counts 0.
   - Update `_deploySecuritize` for the new 10-arg constructor (rolling tests can pass `initialCutoff=0, period=0, valuationDelay=0`).

- [ ] **Step 5: Run** — `forge build && forge test --match-path "test/adapters/ll-adapter/ProviderAccounts.t.sol" -vv`. Expected: PASS. Also run `forge test --no-match-path "*Mainnet*"` to catch other references (e.g. `LiquidLaneAdapterAllTokensBenchmark` compiles against new constructors).
- [ ] **Step 6: Commit** — `git add -A && git commit -m "feat: cutoff-based Securitize redemptions, unified Superstate settlement"`

---

### Task 5: Rewrite `DigiFTAccount` on `SettlementAccount`; bEQTY duration 1d→7d

**Files:**
- Rewrite: `src/contracts/adapters/ll-adapter/DigiFTAccount.sol`
- Modify: `src/interfaces/adapters/ll-adapter/digift/IDigiFTAccount.sol`
- Delete: `src/interfaces/adapters/ll-adapter/digift/IDigiFTSubAccount.sol`
- Modify: `src/contracts/adapters/ll-adapter/tokens-to-redeem/bEQTY_Account.sol`
- Modify: `test/adapters/ll-adapter/DigiFTAccount.t.sol`, `test/adapters/ll-adapter/AccountsBase.t.sol` (constant + helper)

- [ ] **Step 1: New `DigiFTAccount.sol`** (full file; DigiFT keeps no cooldown — pass 0, behavior identical to today's request-every-sync)

```solidity
// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {SettlementAccount, SettlementSubAccount} from "./common/SettlementAccount.sol";

import {IDigiFTAccount} from "../../../interfaces/adapters/ll-adapter/digift/IDigiFTAccount.sol";
import {IDigiFTSubRedManagement} from "../../../interfaces/adapters/ll-adapter/digift/IDigiFTSubRedManagement.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title DigiFTAccount
/// @notice Account for DigiFT normal redemptions.
contract DigiFTAccount is SettlementAccount, IDigiFTAccount {
    /* IMMUTABLES */

    /// @inheritdoc IDigiFTAccount
    address public immutable SUB_RED_MANAGEMENT;

    /* CONSTRUCTOR */

    /// @notice Creates the DigiFT account implementation.
    constructor(
        address oracle,
        address factory,
        address tokenToRedeem,
        address subRedManagement,
        uint48 settlementDuration,
        address cowSwapSettlement
    ) SettlementAccount(oracle, factory, 0, tokenToRedeem, 0, 0, 0, settlementDuration, cowSwapSettlement) {
        SUB_RED_MANAGEMENT = subRedManagement;
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Deploys a DigiFT request-holder subaccount.
    function _createSubAccount() internal override returns (address subAccount) {
        return address(new DigiFTSubAccount(_asset, address(this), TOKEN_TO_REDEEM, SUB_RED_MANAGEMENT));
    }
}

/// @title DigiFTSubAccount
/// @notice Request-holder subaccount for one DigiFT normal redemption.
contract DigiFTSubAccount is SettlementSubAccount {
    using SafeERC20 for IERC20;

    /* IMMUTABLES */

    /// @dev DigiFT normal redemption manager.
    address internal immutable SUB_RED_MANAGEMENT;

    /* CONSTRUCTOR */

    /// @notice Creates the DigiFT request-holder subaccount.
    constructor(address asset, address account, address tokenToRedeem, address subRedManagement)
        SettlementSubAccount(asset, account, tokenToRedeem)
    {
        SUB_RED_MANAGEMENT = subRedManagement;
        IERC20(tokenToRedeem).forceApprove(subRedManagement, type(uint256).max);
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Submits held DigiFT tokens into a normal redemption.
    function _executeRedemption() internal override {
        IDigiFTSubRedManagement(SUB_RED_MANAGEMENT)
            .redeem(TOKEN_TO_REDEEM, ASSET, IERC20(TOKEN_TO_REDEEM).balanceOf(address(this)), block.timestamp);
    }
}
```

`IDigiFTAccount.sol` becomes:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ISettlementAccount} from "../ISettlementAccount.sol";

/**
 * @title IDigiFTAccount
 * @notice Interface for DigiFT liquidity lane accounts.
 */
interface IDigiFTAccount is ISettlementAccount {
    /* FUNCTIONS */

    /**
     * @notice Returns the DigiFT normal redemption manager.
     * @return subRedManagement The redemption manager address.
     */
    function SUB_RED_MANAGEMENT() external view returns (address subRedManagement);
}
```

- [ ] **Step 2: `bEQTY_Account.sol`** — rename `TOKEN_PENDING_ASSETS_DURATION` → `TOKEN_SETTLEMENT_DURATION` and change `1 days` → `7 days` (published DigiFT settlement is up to 5 days). Constructor arg order unchanged.

- [ ] **Step 3: Update tests** — in `AccountsBase.t.sol` rename `DIGIFT_PENDING_ASSETS_DURATION` to `DIGIFT_SETTLEMENT_DURATION = 7 days` and update the DigiFT deploy helper for the new constructor + `MockPriceDataOracle`. In `DigiFTAccount.t.sol`, adapt assertions: write-off now occurs at `request + 7 days` (was 1 day); pending valuation is live (oracle-priced amount) until the oracle's `updatedAt ≥ request time` freezes it — when the mock oracle is constructed with `updatedAt == block.timestamp`, the first `sync()` freezes at the request-time price, matching the old fixed-value semantics for unchanged-price scenarios. Keep the existing settlement-sweep and isSettled flow assertions (sub still sweeps `ASSET` to parent).

- [ ] **Step 4: Run** — `forge test --match-path "test/adapters/ll-adapter/DigiFTAccount.t.sol" -vv && forge test --no-match-path "*Mainnet*"`. Expected: PASS.
- [ ] **Step 5: Commit** — `git add -A && git commit -m "refactor: DigiFT account on settlement base with 7-day write-off"`

---

### Task 6: Makina `min(quote, live)` pending cap

**Files:**
- Modify: `src/contracts/adapters/ll-adapter/MakinaAccount.sol`
- Modify: `src/interfaces/adapters/ll-adapter/makina/IMakinaAccount.sol`
- Test: `test/adapters/ll-adapter/MakinaAccount.t.sol`

Makina settles each request at **no more than the value quoted when it was made** (docs.makina.finance/concepts/machine/redemptions), so live-rate valuation overvalues pending requests when the share price rises.

- [ ] **Step 1: Write the failing test** — read `MakinaAccount.t.sol` and its mocks first; add (following its existing deploy/mock helpers):

```solidity
    function testMakinaPendingRequestValueIsCappedAtRequestTimeQuote() public {
        // deploy via the file's existing helper; request redemption of `amount` at share price P
        // (use the existing mock redeemer/machine setup, then:)

        // 1) price rises: live value would exceed the quote -> totalAssets stays at the quote
        //    set the mock share-price oracle to 1.5 * P
        //    assertEq(account-pending-part-of-totalAssets, quoteAssets);

        // 2) price falls below the quote -> totalAssets follows the live (lower) value
        //    set the mock share-price oracle to 0.5 * P
        //    assertEq(account-pending-part-of-totalAssets, halfQuoteAssets);
    }
```

(Write it as a concrete test against the file's actual mocks — the two assertions above are the required behavior. Also assert `requestQuotes(requestId)` is non-zero after request and zero after the claim is finalized.)

- [ ] **Step 2: Verify failure** — `forge test --match-path "test/adapters/ll-adapter/MakinaAccount.t.sol" -vv`. Expected: new test FAILS on assertion 1 (live value used).

- [ ] **Step 3: Implement** in `MakinaAccount.sol`:

Add state + interface entry:

```solidity
    /// @inheritdoc IMakinaAccount
    mapping(uint64 requestId => uint256 assets) public requestQuotes;
```

`IMakinaAccount.sol` addition:

```solidity
    /**
     * @notice Returns the request-time vault-asset quote capping a pending request's value.
     * @param requestId The redemption receipt id.
     * @return assets The quoted vault-asset value (0 for requests created before quoting).
     */
    function requestQuotes(uint64 requestId) external view returns (uint256 assets);
```

Replace `_requestRedeem` body:

```solidity
    /// @dev Submits held token-to-redeem balance to the Makina redeemer and quotes its current value.
    function _requestRedeem() internal override {
        uint256 amount = IERC20(TOKEN_TO_REDEEM).balanceOf(address(this));
        uint64 requestId = uint64(IMakinaRedeemer(REDEEMER).requestRedeem(amount, address(this), 0));

        requestIds.push(requestId);
        requestQuotes[requestId] = _tokenToRedeemToAssets(amount);
    }
```

In `_totalAssets`, replace the pre-finalization leg:

```solidity
                try IMakinaRedeemer(REDEEMER).getShares(requestId) returns (uint256 shares) {
                    uint256 quote = requestQuotes[uint64(requestId)];
                    uint256 live = _tokenToRedeemToAssets(shares);
                    assets += quote == 0 || live < quote ? live : quote;
                } catch {}
```

(The `quote == 0` branch keeps pre-upgrade requests valued live instead of at zero.)

In `_finalizeRequests`, delete the quote when a claim succeeds (before the swap-pop):

```solidity
            try IMakinaRedeemer(REDEEMER).claimAssets(requestIds[index]) returns (uint256) {
                delete requestQuotes[requestIds[index]];
                requestIds[index] = requestIds[requestIds.length - 1];
                requestIds.pop();
            } catch {}
```

- [ ] **Step 4: Run** — same test path. Expected: PASS (including existing tests).
- [ ] **Step 5: Commit** — `git add -A && git commit -m "fix: cap Makina pending value at request-time quote"`

---

### Task 7: AsyncRedeem claimable precision + delete `CentrifugeAccount` passthrough

**Files:**
- Modify: `src/contracts/adapters/ll-adapter/common/AsyncRedeemAccount.sol` (`_totalAssets` only)
- Modify: `src/interfaces/adapters/ll-adapter/IAsyncRedeemVault.sol` (add `maxWithdraw`)
- Delete: `src/contracts/adapters/ll-adapter/CentrifugeAccount.sol`, `src/interfaces/adapters/ll-adapter/centrifuge/ICentrifugeAccount.sol`
- Modify: 6 token files `ACRDX_Account.sol`, `JAAA_Account.sol`, `JTRSY_Account.sol`, `deCRDX_Account.sol`, `deJAAA_Account.sol`, `deJTRSY_Account.sol` (base → `AsyncRedeemAccount`)
- Modify: `test/adapters/ll-adapter/CentrifugeAccount.t.sol`, `test/adapters/ll-adapter/AsyncRedeemAccount.t.sol`, `test/adapters/ll-adapter/AccountsBase.t.sol` (imports + `MockAsyncRedeemVault.maxWithdraw`)

- [ ] **Step 1: `IAsyncRedeemVault.sol`** — add:

```solidity
    /**
     * @notice Returns the claimable asset amount across processed redemptions, at fulfillment prices.
     * @param owner The request controller.
     * @return maxAssets The claimable asset amount.
     */
    function maxWithdraw(address owner) external view returns (uint256 maxAssets);
```

- [ ] **Step 2: `AsyncRedeemAccount._totalAssets`** — value the claimable leg at the frozen fulfillment price via `maxWithdraw`, keep live conversion only for the pending leg:

```solidity
    /// @dev Returns pending async redemption request value plus claimable value at fulfillment prices.
    function _totalAssets() internal view virtual override returns (uint256 assets) {
        address asyncRedeemVault = _asyncRedeemVault();

        for (uint256 i; i < requestIds.length; ++i) {
            assets += IAsyncRedeemVault(asyncRedeemVault)
                .convertToAssets(IAsyncRedeemVault(asyncRedeemVault).pendingRedeemRequest(requestIds[i], address(this)));
        }

        assets += IAsyncRedeemVault(asyncRedeemVault).maxWithdraw(address(this));
    }
```

- [ ] **Step 3: Delete `CentrifugeAccount.sol` + `ICentrifugeAccount.sol`**, then update the 6 Centrifuge token files — each changes only its import and base, e.g. `JAAA_Account.sol`:

```solidity
// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {AsyncRedeemAccount} from "../common/AsyncRedeemAccount.sol";
import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";

contract JAAA_Account is AsyncRedeemAccount {
    address internal constant TOKEN_ADDRESS = 0x5a0F93D040De44e78F251b03c43be9CF317Dcf64;
    uint48 internal constant TOKEN_COOLDOWN = 1 days;

    constructor(address oracle, address factory, address cowSwapSettlement)
        AsyncRedeemAccount(oracle, factory, TOKEN_COOLDOWN, TOKEN_ADDRESS, cowSwapSettlement)
    {}
}

contract JAAA_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}
```

(Apply identically to the other 5 with their own constants. `AsyncRedeemAccount` stays `abstract`; the token contracts are the deployable leaves.)

- [ ] **Step 4: Tests** — `grep -rn "CentrifugeAccount" test/ script/` and update imports/usages to `AsyncRedeemAccount` or the token contracts. Extend `MockAsyncRedeemVault` (in `AccountsBase.t.sol`) with `maxWithdraw(address)`: record claimable ASSETS at fulfillment time (at the share price in effect when the mock fulfills) and return that stored amount; keep `claimableRedeemRequest` returning shares. Add/adapt a test: fulfill a request at price P, then change the mock's live share price — `totalAssets()` must still report the claimable leg at P (frozen), while a separate pending request follows the live price.

- [ ] **Step 5: Run** — `forge test --no-match-path "*Mainnet*" -vv`. Expected: PASS.
- [ ] **Step 6: Commit** — `git add -A && git commit -m "fix: value claimable async redemptions at fulfillment price"`

---

### Task 8: `MidasCutoffAccount` + switch `mGLOBAL_Account`

**Files:**
- Modify: `src/contracts/adapters/ll-adapter/MidasAccount.sol` (append `MidasCutoffAccount`)
- Modify: `src/interfaces/adapters/ll-adapter/midas/IMidasAccount.sol` (only if `@inheritdoc` targets require; expected: no change)
- Modify: `src/contracts/adapters/ll-adapter/tokens-to-redeem/mGLOBAL_Account.sol`
- Test: create `test/adapters/ll-adapter/MidasCutoffAccount.t.sol`

- [ ] **Step 1: Write the failing test** (self-contained mocks; initialization data mirrors `ProviderAccounts.t.sol`'s `_initData(asset, tokenToRedeem)` → `abi.encode(vault, adapter)` pattern — copy the local `MockVault`/init helper approach from `AccountsBase.t.sol`):

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {MidasCutoffAccount} from "../../../src/contracts/adapters/ll-adapter/MidasAccount.sol";
import {MidasOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/MidasOracle.sol";
import {MigratablesFactory} from "../../../src/contracts/common/MigratablesFactory.sol";
import {
    REQUEST_STATUS_PENDING
} from "../../../src/interfaces/adapters/ll-adapter/midas/IMidasAccount.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20_ is ERC20 {
    uint8 internal immutable _decimals;

    constructor(string memory name_, uint8 decimals_) ERC20(name_, name_) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

contract MockAggregator {
    int256 public answer;
    uint256 public updatedAt;

    function setRound(int256 answer_, uint256 updatedAt_) external {
        answer = answer_;
        updatedAt = updatedAt_;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, answer, updatedAt, updatedAt, 1);
    }
}

contract MockMidasDataFeed {
    address public aggregator;

    constructor(address aggregator_) {
        aggregator = aggregator_;
    }

    function getDataInBase18() external view returns (uint256) {
        return uint256(MockAggregator(aggregator).answer()) * 1e10; // 8 -> 18 decimals
    }
}

contract MockMidasRedemptionVault {
    struct Request {
        address sender;
        address tokenOut;
        uint8 status;
        uint256 amountMToken;
        uint256 mTokenRate;
        uint256 tokenOutRate;
    }

    address public mTokenDataFeed;
    MockERC20_ internal immutable _mToken;
    uint256 internal _nextRequestId;
    mapping(uint256 => Request) public redeemRequests;
    mapping(address => Tuple) internal _tokensConfig;

    struct Tuple {
        address dataFeed;
        uint256 allowance;
        uint256 fee;
        bool stable;
    }

    constructor(address mToken, address dataFeed) {
        _mToken = MockERC20_(mToken);
        mTokenDataFeed = dataFeed;
    }

    function setTokenConfig(address token, address dataFeed) external {
        _tokensConfig[token] = Tuple(dataFeed, 0, 0, true);
    }

    function tokensConfig(address token) external view returns (address, uint256, uint256, bool) {
        Tuple memory t = _tokensConfig[token];
        return (t.dataFeed, t.allowance, t.fee, t.stable);
    }

    function redeemRequest(address tokenOut, uint256 amountMToken) external returns (uint256 requestId) {
        requestId = _nextRequestId++;
        _mToken.burn(msg.sender, amountMToken);
        redeemRequests[requestId] = Request(msg.sender, tokenOut, 0, amountMToken, 0, 0);
    }

    function process(uint256 requestId) external {
        redeemRequests[requestId].status = 1;
    }
}
```

Check the exact member layout the production `IMidasRedemptionVault.redeemRequests`/`tokensConfig` destructuring expects (the account destructures `(,, uint8 status, uint256 amountMToken, uint256 mTokenRate,)` and `(address dataFeed,,,)`) and shape the mock's return tuples to match the interface file exactly.

Test contract scenarios (deploy `MidasCutoffAccount` directly via `MigratablesFactory` with: oracle = `new MidasOracle(address(dataFeed))`, asset = 6-decimals USDC mock, tokenToRedeem = 18-decimals mGLOBAL mock, redemptionToken = asset, cutoff schedule `CUTOFF=now+10 days`, `PERIOD=30 days`, `VALUATION_DELAY=5 days`, `SETTLEMENT_DURATION=45 days`, cooldown `6 days`):

1. `testRequestRegistersCohortAndValuesLive` — mint 100e18 mGLOBAL to account, aggregator at `0.93e8, updatedAt=now`; `sync()`; assert `pendingCohorts(requestId)` cutoff == CUTOFF and `totalAssets() == 93e6`; move aggregator to `0.95e8` → `totalAssets() == 95e6` (live).
2. `testFreezesAtFirstPrintAfterPricingDate` — warp to `CUTOFF + 5 days + 1` with aggregator `updatedAt < CUTOFF + 5 days` → `sync()` does not freeze (still live); set aggregator `(0.94e8, CUTOFF + 5 days + 2)`; `sync()` freezes; set aggregator `1e8` → `totalAssets()` still `94e6`.
3. `testWriteOffAndLateFulfillment` — warp past `CUTOFF + 5 days + 45 days` → `totalAssets()` pending leg 0; then `vault.process(requestId)` + deal USDC to account → `sync()` clears the request id and `requestQuotes`-like state (assert `pendingCohorts(requestId).amount == 0` and request id list emptied).
4. `testSecondRequestJoinsNextCohort` — after CUTOFF passes, new mint + `vm.prank(owner)`-driven `sync()` (owner bypasses cooldown) → its cohort == `CUTOFF + 30 days`.
5. `testSetCutoffScheduleOnlyOwner` — non-owner reverts (`OwnableUnauthorizedAccount`), owner succeeds.

- [ ] **Step 2: Verify failure** — `forge test --match-path "test/adapters/ll-adapter/MidasCutoffAccount.t.sol"`. Expected: compile error (`MidasCutoffAccount` missing).

- [ ] **Step 3: Implement** — append to `MidasAccount.sol` (add imports: `CutoffPricer` from `./common/CutoffPricer.sol`, `IPriceDataOracle` from `../../../interfaces/adapters/ll-adapter/IPriceDataOracle.sol`):

```solidity
/// @title MidasCutoffAccount
/// @notice Midas account for cutoff-cohort redemptions: pending requests compound until the cohort
///         pricing date, then freeze at the first vault-feed print at/after it.
contract MidasCutoffAccount is MidasAccount, CutoffPricer {
    /* CONSTRUCTOR */

    /// @notice Creates the cutoff-cohort Midas account implementation.
    constructor(
        address oracle,
        address factory,
        uint48 cooldown,
        address tokenToRedeem,
        address redemptionToken,
        address redemptionVault,
        uint48 initialCutoff,
        uint48 initialCutoffPeriod,
        uint48 valuationDelay,
        uint48 settlementDuration,
        address cowSwapSettlement
    )
        MidasAccount(oracle, factory, cooldown, tokenToRedeem, redemptionToken, redemptionVault, cowSwapSettlement)
        CutoffPricer(initialCutoff, initialCutoffPeriod, valuationDelay, settlementDuration)
    {}

    /* PUBLIC FUNCTIONS (OWNER) */

    /// @notice Updates the cutoff schedule. Only callable by the owner.
    function setCutoffSchedule(uint48 nextCutoff, uint48 period) public onlyOwner {
        _setCutoffSchedule(nextCutoff, period);
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Submits inventory to the Midas redemption vault and registers the request's cohort.
    function _requestRedeem() internal override {
        uint256 amount = IERC20(TOKEN_TO_REDEEM).balanceOf(address(this));
        super._requestRedeem();
        _registerPending(requestIds[requestIds.length - 1], amount);
    }

    /// @dev Freezes cohort rates and clears Midas redemption requests that are no longer pending.
    function _finalizeRequests() internal override {
        for (uint256 i = requestIds.length; i > 0; --i) {
            uint256 index = i - 1;
            uint64 requestId = requestIds[index];

            _tryFreezePending(requestId);

            (,, uint8 status,,,) = IMidasRedemptionVault(REDEMPTION_VAULT).redeemRequests(requestId);
            if (status == REQUEST_STATUS_PENDING) {
                continue;
            }

            _clearPending(requestId);
            requestIds[index] = requestIds[requestIds.length - 1];
            requestIds.pop();
        }
    }

    /// @dev Returns pending request value priced by cutoff cohorts.
    function _pendingAssets() internal view override returns (uint256 assets) {
        for (uint256 i; i < requestIds.length; ++i) {
            assets += _pendingValue(requestIds[i]);
        }
    }

    /// @inheritdoc CutoffPricer
    function _cutoffPriceData() internal view override returns (uint256 price, uint48 updatedAt) {
        return IPriceDataOracle(ORACLE).getPriceData();
    }

    /// @inheritdoc CutoffPricer
    function _cutoffToAssets(uint256 amount, uint256 rate) internal view override returns (uint256 assets) {
        return _tokenToRedeemToAssets(amount, rate);
    }

    /* INITIALIZATION */

    /// @dev Initializes the account and applies the cutoff schedule.
    function _initialize(uint64 initialVersion, address initOwner, bytes memory data) internal override {
        super._initialize(initialVersion, initOwner, data);
        __CutoffPricer_init();
    }
}
```

- [ ] **Step 4: Switch `mGLOBAL_Account.sol`** (`1_782_432_000` = 2026-06-26 00:00:00 UTC; cutoff day is unpublished ops detail — owner-adjustable):

```solidity
// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {MidasCutoffAccount} from "../MidasAccount.sol";
import {MidasOracle} from "../oracles/MidasOracle.sol";
import {MigratablesFactory} from "../../../common/MigratablesFactory.sol";

import {IMidasRedemptionVault} from "../../../../interfaces/adapters/ll-adapter/midas/IMidasRedemptionVault.sol";
import {IMidasTokenAccount} from "../../../../interfaces/adapters/ll-adapter/midas/IMidasTokenAccount.sol";

contract mGLOBAL_Account is MidasCutoffAccount, IMidasTokenAccount {
    uint48 internal constant TOKEN_COOLDOWN = 6 days;
    uint48 public constant MAX_WITHDRAWAL_DELAY = 65 days;
    /// @dev 2026-06-26 00:00:00 UTC monthly request cutoff; owner-maintained thereafter.
    uint48 internal constant INITIAL_CUTOFF = 1_782_432_000;
    uint48 internal constant INITIAL_CUTOFF_PERIOD = 30 days;
    uint48 internal constant TOKEN_VALUATION_DELAY = 5 days;
    uint48 internal constant TOKEN_SETTLEMENT_DURATION = 45 days;
    address internal constant MAINNET_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant TOKEN_ADDRESS = 0x7433806912Eae67919e66aea853d46Fa0aef98A8;
    address internal constant REDEMPTION_VAULT_ADDRESS = 0x1e0fd66753198c7b8bA64edEe8d41D8628Bf20D7;

    constructor(address factory, address cowSwapSettlement)
        MidasCutoffAccount(
            address(new MidasOracle(address(IMidasRedemptionVault(REDEMPTION_VAULT_ADDRESS).mTokenDataFeed()))),
            factory,
            TOKEN_COOLDOWN,
            TOKEN_ADDRESS,
            MAINNET_USDC,
            REDEMPTION_VAULT_ADDRESS,
            INITIAL_CUTOFF,
            INITIAL_CUTOFF_PERIOD,
            TOKEN_VALUATION_DELAY,
            TOKEN_SETTLEMENT_DURATION,
            cowSwapSettlement
        )
    {}
}

contract mGLOBAL_AccountFactory is MigratablesFactory {
    constructor(address newOwner) MigratablesFactory(newOwner) {}
}
```

- [ ] **Step 5: Run** — `forge test --match-path "test/adapters/ll-adapter/MidasCutoffAccount.t.sol" -vv && forge test --no-match-path "*Mainnet*"`. Expected: PASS.
- [ ] **Step 6: Commit** — `git add -A && git commit -m "feat: cutoff-cohort Midas account for mGLOBAL"`

---

### Task 9: Mainnet-fork spec tests

**Files:**
- Modify: `test/adapters/ll-adapter/tokens_to_redeem/MidasTokensToRedeemMainnet.t.sol` (mGLOBAL spec entry)
- Modify: `test/adapters/ll-adapter/tokens_to_redeem/TokensToRedeemMainnet.t.sol` (ACRED/USCC/bEQTY entries)
- Possibly: `test/adapters/LiquidLaneAdapterAllTokensBenchmark.t.sol`

- [ ] **Step 1:** If `ETH_RPC_URL` is unset, run `forge build` + the non-fork suite only and note fork tests as not-run in the final report; otherwise run the two fork suites first to see what breaks.
- [ ] **Step 2:** Update specs: mGLOBAL's expected implementation/behavior assertions for `MidasCutoffAccount` (e.g. cutoff getters: after `create`, `cutoff() == 1_782_432_000`, `cutoffPeriod() == 30 days`); ACRED's entry must construct with the unchanged 3-arg token constructor but any direct `SecuritizeAccount` constructions get the new 10-arg signature and a `getPriceData`-capable oracle (RedStone ACRED feed `0xD6BcbbC87bFb6c8964dDc73DC3EaE6d08865d51C` is AggregatorV3-compatible → `ChainlinkOracle` works); bEQTY assertions move from 1-day to 7-day write-off.
- [ ] **Step 3:** Run available suites; fix fallout. Expected: PASS (or documented as skipped for missing RPC).
- [ ] **Step 4: Commit** — `git add -A && git commit -m "test: cutoff redemption mainnet specs"`

---

### Task 10: Full verification

- [ ] `forge fmt && forge build` — clean, no warnings introduced.
- [ ] `forge test --no-match-path "*Mainnet*"` — full non-fork suite green.
- [ ] Fork suites if RPC available.
- [ ] `grep -rn "ISecuritizeSubAccount\|ISuperstateSubAccount\|IDigiFTSubAccount\|ISecuritizeToken\|CentrifugeAccount\|PENDING_ASSETS_DURATION" src/ test/ script/` — no stale references (PENDING_ASSETS_DURATION may legitimately remain only if some unrelated contract still uses it — expected result: none).
- [ ] Final commit of any stragglers; do NOT push.
