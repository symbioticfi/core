# Cutoff-Based Redemptions & Settlement-Account Unification — Design

Date: 2026-06-11
Status: Approved direction (Option A: mixin + unified settlement family; oracle `updatedAt`-based rate freezing; all corrective fixes included). Code minimization targets issuer-level and `common/` contracts only — per-token files in `tokens-to-redeem/` are intentionally left verbose.

## 1. Problem

Two integrations have **cutoff-based (cohort) redemptions** that the current `common/` bases (`Account` → `CooldownAccount` → `AsyncRedeemAccount`) cannot represent fairly:

- **ACRED (Securitize)** — quarterly repurchase windows (2026 feeder deadlines: 04/30, 07/31, 10/30, 01/29/2027; underlying fund pricing ≈ deadline + 5 days).
- **mGLOBAL (Midas)** — monthly request cutoff (~26th, unpublished/ops-variable), cohort priced at the following month-end NAV, paid ~1 month later (max ≈ 65 days).

Additionally, re-research of every Account surfaced correctness deltas (§2) and a large duplication block: `SecuritizeAccount`, `SuperstateAccount`, and `DigiFTAccount` are ~95% identical (501 lines total).

## 2. Research findings driving the design

### ACRED (verified on-chain + SEC filings + Securitize feed/docs)
1. **`burn()` is unusable**: the deployed ACRED DSToken's `burn` is `onlyIssuerOrTransferAgentOrAbove`; the current `SecuritizeSubAccount.requestRedeem()` would revert on mainnet. The actual redemption notice is a **plain ERC-20 transfer to the redemption wallet** `0xbb543C77436645C8b95B64eEc39E3C0d48D4842b` (per `public-feed.securitize.io/asset-info?symbol=ACRED`; Ethereum has no off-ramp contract).
2. **Quarterly single-batch settlement with pro-rata fills**: observed Q2-2026 — all tenders settled in one batch on 05/13 (deadline 04/30), fill ratio 34.78%; USDC paid for the filled portion and **unfilled ACRED re-minted back to the sender address**. Remainders do not roll over; they must be re-tendered.
3. NAV **keeps accruing until the Repurchase Pricing Date** (= underlying deadline ≈ feeder deadline + 5 days). Observed settlement lag 12–20 days after the feeder deadline; structural max ≈ 30 days (suspension tail exists).
4. On-chain oracle: RedStone `ACRED_FUNDAMENTAL` (AggregatorV3-compatible, ~daily updates, `updatedAt` available).

### mGLOBAL (verified contract source + Midas docs + rwa.xyz)
1. The redemption vault (`MGlobalRedemptionVaultWithSwapper` @ `0x1e0fd667…`) pays `amountMToken × rate supplied at approval` (bulk path uses the vault feed at fulfillment) — pending requests **compound until the cohort valuation date, then the payout is fixed** at that cohort NAV while the feed keeps stepping monthly → pure live-rate valuation overvalues a post-valuation request by up to ~1 month of yield.
2. The vault's `mTokenDataFeed` is the **"PriceLowered" feed = NAV × 0.93**; the 7% exit fee is refunded **out-of-band**. Current `MidasOracle` wiring already uses the vault feed → on-chain payout valuation is correct; the refund leg is NOT counted until received (conservative; ops to confirm the refund destination).
3. Feed aggregator exposes `updatedAt` (monthly prints ~15th–16th); the DataFeed wrapper reverts when >60 days stale.
4. No other Midas token is cutoff-based (all 23 checked; mF-ONE request-time pricing = existing `MidasNonCompAccount` confirmed correct). mFARM, mBTC, msyrupUSD, mevBTC are retired/paused (informational; no action in this change).

### Other issuers
- **Superstate USCC**: rolling T+1/T+2 at request-day NAV → current freeze-at-request + 3-day write-off is correct.
- **DigiFT bEQTY**: published settlement "up to five days" → `PENDING_ASSETS_DURATION` must go 1 day → **7 days**.
- **Makina DUSD**: payout is capped at the **request-time quote** (`min(quote, live)`); current live-rate valuation overvalues in rising markets → add quote cap.
- **Centrifuge (7540)**: the claimable portion is frozen at the fulfillment price; valuing it with live `convertToAssets` drifts → value claimable via `maxWithdraw`.
- **GAIB sAID** (monthly queue but request-time-fixed AID amount), **Pareto** (monthly epochs, receipt-token valued), **Theo/Noon/3Jane/EtherFi/Lido**: current models match published mechanics; no changes.

## 3. Architecture

```
Account
└── CooldownAccount
    ├── AsyncRedeemAccount            (made concrete; CentrifugeAccount deleted)
    ├── MidasAccount (Comp/NonComp)
    │   └── MidasCutoffAccount  (NEW)         + CutoffPricer
    └── SettlementAccount       (NEW, common/) + CutoffPricer
        ├── SecuritizeAccount   (rewritten shim: transfer-to-wallet notice)
        ├── SuperstateAccount   (shim: offchainRedeem)
        └── DigiFTAccount       (shim: subRedManagement.redeem; cooldown 0)

CutoffPricer (NEW, common/, standalone abstract mixin — no Account inheritance)
SettlementSubAccount (NEW, common/, base request-holder; 3 tiny issuer subclasses)
```

A cutoff redemption is fully described by **three timing parameters + one freezing rule**:
- requests registered at time T are assigned cohort `cutoff = nextCutoff(T)`;
- the cohort is priced at `cutoff + VALUATION_DELAY`;
- value is written off (counted as 0, entry retained) after `pricing + SETTLEMENT_DURATION`;
- fair value = `amount × live oracle` until the cohort pricing rate is captured, then frozen.

**Degenerate parameters reproduce today's rolling issuers** (`cutoff schedule = none ⇒ cohort = request time`, `VALUATION_DELAY = 0` ⇒ freeze at the first oracle print at/after request — i.e. the request-day NAV; `SETTLEMENT_DURATION` = existing pending-assets duration). This is why one abstraction covers Securitize, Superstate, DigiFT, and mGLOBAL.

### 3.1 `common/CutoffPricer.sol` (new, ~120 lines)

Standalone abstract mixin (avoids inheritance diamonds; hosts already extend `Account` lineages).

State / immutables:
- `uint48 immutable VALUATION_DELAY` — cutoff → cohort pricing moment.
- `uint48 immutable SETTLEMENT_DURATION` — pricing → write-off.
- `uint48 cutoff`, `uint48 cutoffPeriod` — next cutoff and auto-roll period; initialized from constructor immutables (anchor values), owner-adjustable via `setCutoffSchedule(uint48 nextCutoff, uint48 period)` (calendar months/quarters drift vs fixed periods; owner corrects occasionally). `cutoff == 0` ⇒ rolling mode (cohort = registration time).
- `struct PendingCohort { uint128 amount; uint128 frozenRate; uint48 cutoff; }`
- `mapping(uint256 key => PendingCohort)` — key is a request id or `uint160(subAccount)`.

Internal API (called by hosts):
- `_registerPending(key, amount)` — rolls `cutoff` forward (`while (block.timestamp > cutoff) cutoff += cutoffPeriod`), stores entry with the assigned cohort.
- `_tryFreeze(key)` — if not frozen and `block.timestamp ≥ pricingTime`: read `(price, updatedAt) = _priceData()`; freeze only when `updatedAt ≥ pricingTime && price != 0`. This captures the *first oracle print at/after the cohort pricing date* — for mGLOBAL that is exactly the print embedding the cohort NAV; for ACRED the next daily RedStone print; for rolling issuers the request-day closing NAV.
- `_pendingValue(key) view` — `0` if written off; else `_toAssets(amount, frozenRate != 0 ? frozenRate : livePrice)`.
- `_clearPending(key)`.

Host hooks (virtual): `_priceData() → (uint256 price, uint48 updatedAt)`, `_toAssets(uint256 amount, uint256 rate) → uint256` (wired to `Account._tokenToRedeemToAssets(amount, rate)`), `owner()` (satisfied by the host's `Ownable`).

### 3.2 Oracle extension (the "slight change" to existing common code)

New `IPriceDataOracle is IOracle { function getPriceData() external view returns (uint256 price, uint48 updatedAt); }`.

- `MidasOracle`: add `getPriceData()` = `(getDataInBase18(), aggregator.latestRoundData().updatedAt)`; add `aggregator()` to `IMidasDataFeed` (the deployed DataFeed exposes it).
- `ChainlinkOracle` / `ChainlinkPriceFeed`: add a variant returning the price plus `updatedAt` (for the dual-aggregator case: the older of the two timestamps).
- Hosts that use `CutoffPricer` REQUIRE an `IPriceDataOracle`; no silent fallback. `getPrice()` consumers are unchanged.

### 3.3 `common/SettlementAccount.sol` + `SettlementSubAccount` (new, replaces 3 near-clones)

`SettlementAccount is CooldownAccount, CutoffPricer` (abstract):
- `address[] subAccounts`; `mapping(uint256 key => uint256) receivedValues` — cumulative settlement value received per sub, in vault assets (token receipts valued at sweep-time rates).
- `_requestRedeem()`: `sub = _createSubAccount()` (virtual), `_registerPending(uint160(sub), balance)`, transfer balance to sub, `sub.requestRedeem()`.
- `_finalizeRequests()`: reverse loop — `_tryFreeze`, `(assets, tokens) = sub.sync()` (sweeps and reports), `receivedValues[sub] += assets + tokenValue(tokens)`; the sub is settled (`_clearPending` + `delete receivedValues` + swap-pop) only once `receivedValues[sub] ≥ cohortValue(sub)` (**value-covered settlement**). This supports multi-tranche settlements (e.g. DigiFT pays in tranches), makes dust donations harmless (they reduce the remaining receivable one-for-one instead of writing it off), and keeps written-off-but-unpaid subs tracked indefinitely so late settlements are still swept and recovered.
- `_totalAssets()`: per sub — `holdings = asset.balanceOf(sub) + tokenValue(token.balanceOf(sub))`; `remaining = cohortValue(sub) − receivedValues[sub]` (0 once written off); `assets += holdings + remaining.saturatingSub(holdings)` (i.e. `max(remaining, holdings)` per sub — the receivable shrinks one-for-one as settlement value arrives, and ACRED re-mints are priced as live token holdings without double counting).

`SettlementSubAccount` (base, dumb holder):
- immutables `ACCOUNT, ASSET, TOKEN_TO_REDEEM`; stateless.
- `requestRedeem()` (onlyAccount) → virtual `_executeRedemption()`.
- `sync()` (onlyAccount) → sweeps ASSET and TOKEN_TO_REDEEM balances to ACCOUNT and returns both swept amounts; settledness is decided by the parent from cumulative received value, not by the sub.

Issuer shims (each ~25–40 lines, sub subclass in the same file):
- **SecuritizeAccount**: immutable `REDEMPTION_WALLET`; sub `_executeRedemption()` = `safeTransfer(REDEMPTION_WALLET, balance)` (replaces the broken `burn()`). Re-minted partial-fill ACRED is swept back by the base `sync()` and re-tendered automatically next window by the parent's normal flow.
- **SuperstateAccount**: sub `_executeRedemption()` = `offchainRedeem(balance)`. Rolling parameters reproduce current behavior with two intended deltas: pre-freeze pending value floats with the live oracle (instead of being fixed at the request-time rate), and `totalAssets` now consults the oracle for pending subs — reverting on a zero price during that window.
- **DigiFTAccount**: sub approves `SUB_RED_MANAGEMENT` in constructor; `_executeRedemption()` = `subRedManagement.redeem(token, asset, balance, block.timestamp)`. Moves onto `CooldownAccount` with `COOLDOWN = 0` (identical request-every-sync behavior).

### 3.4 `MidasCutoffAccount` (new, issuer-level, ~60 lines)

`is MidasAccount, CutoffPricer` (no diamond — the mixin is standalone):
- `_requestRedeem()`: read balance, `super._requestRedeem()`, `_registerPending(lastRequestId, amount)`.
- `_finalizeRequests()`: per tracked id — `_tryFreeze(id)`; clear `pendingCohorts` alongside the existing processed-id removal (loop implemented locally instead of `super` to clear both in one pass).
- `_pendingAssets()`: `Σ _pendingValue(id)` (replaces the Comp loop for this account type).

`mGLOBAL_Account` switches base `MidasCompAccount` → `MidasCutoffAccount` and supplies schedule constants. All other Midas tokens stay on Comp/NonComp.

### 3.5 Corrective fixes (small, local)

1. **DigiFT bEQTY**: `TOKEN_PENDING_ASSETS_DURATION` 1 day → 7 days (becomes `SETTLEMENT_DURATION`).
2. **MakinaAccount**: store the request-time asset quote per request id; pre-finalization valuation = `min(live, quote)`; clear on finalize/claim.
3. **AsyncRedeemAccount**: value the claimable leg via the vault's `maxWithdraw(address(this))` (fulfillment-price-frozen) once per vault, keeping live `convertToAssets` only for the pending leg; add `maxWithdraw` to `IAsyncRedeemVault`.
4. **AsyncRedeemAccount made concrete**; `CentrifugeAccount` (pure passthrough) deleted; Centrifuge token accounts extend `AsyncRedeemAccount` directly (keep `ICentrifugeAccount` marker on the token contracts if desired).

## 4. Initial parameters

| | ACRED | mGLOBAL | USCC | bEQTY |
|---|---|---|---|---|
| Cutoff anchor | 2026-07-31 00:00 UTC | 2026-06-26 00:00 UTC (ops-unverified day; owner-adjustable) | rolling (0) | rolling (0) |
| Period | 91 days (owner-corrected per calendar) | 30 days (owner-corrected per calendar) | — | — |
| VALUATION_DELAY | 5 days (underlying pricing date) | 5 days (cohort month-end) | 0 | 0 |
| SETTLEMENT_DURATION | 30 days (observed 12–20 + margin) | 45 days (pricing → payment ≈ 32 d + margin; total ≤ 65 d from request) | 3 days (unchanged) | 7 days (was 1) |
| COOLDOWN (throttle) | 9 days (unchanged) | 6 days (unchanged) | 12 h | 0 |

Cohort boundary uses the start-of-day (UTC) of the deadline date — mis-assigning a boundary request to an *earlier* cohort is conservative (earlier freeze + earlier write-off).

## 5. Edge cases

- **Oracle staleness**: mGLOBAL's DataFeed reverts >60 days stale — matches vault behavior; `_tryFreeze` simply doesn't freeze and `sync()` reverts as today's `totalAssets` would. One intended new failure mode: `totalAssets` now consults the oracle for pending (unfrozen) subs and reverts on a zero price during that window — previously the request-time rate was cached and no oracle read happened.
- **Partial fill (ACRED)**: settlement batch = USDC + re-minted ACRED at the sub; `max(pending, holdings)` valuation hands over smoothly; re-mint is swept and re-tendered next window as a new entry.
- **Zero fill / suspension**: receivable written off after `SETTLEMENT_DURATION` (NAV dips conservatively); the sub stays tracked and any late settlement is still swept (NAV recovers on arrival) — same liveness semantics as today.
- **Multiple requests per window**: allowed (cooldown-throttled); all cohort-mates freeze at the same rate and settle in the same batch.
- **Owner schedule maintenance**: `setCutoffSchedule` only affects *future* cohort assignment; existing entries keep their assigned cutoff.
- **Keeper liveness**: the freeze captures the oracle's *live* print at the first post-pricing sync — for monthly-print tokens a missed month means the *next* print is captured instead of the cohort's. Ops should sync each cohort shortly after its pricing date (at least once before the next oracle print) for exact cohort pricing.
- **Namespaced storage**: `CutoffPricer` keeps its state in ERC-7201 namespaced storage, so migrating existing deployed accounts to `SettlementAccount`-based implementations keeps `subAccounts` slots stable. Migrated instances additionally need their cutoff schedule set via `setCutoffSchedule`, since `__CutoffPricer_init` only runs on fresh initialization.

## 6. Testing

- Unit tests for `CutoffPricer`: cohort assignment across rolls, freeze gating on `updatedAt`, write-off, rolling-mode degeneration, owner schedule updates.
- Mainnet-fork tests (existing `TokensToRedeemMainnet` harness patterns): ACRED transfer-notice + simulated batch settlement with partial re-mint; mGLOBAL request → feed print → freeze → fulfillment; Superstate/DigiFT regression equivalence (behavior preserved under the new base); Makina quote cap; Centrifuge claimable precision.
- Benchmark test updates only as needed for renamed bases. Note: `test/adapters/LiquidLaneAdapterAllTokensBenchmark.t.sol` and `TokensToRedeemMainnet.t.sol` were modified concurrently outside this session — coordinate before editing.

## 7. Open questions / ops follow-ups (non-blocking)

1. **Securitize whitelisting**: each fresh `SettlementSubAccount` address must pass DSToken compliance to receive/transfer ACRED — confirm with Securitize that per-request sub-account addresses can be registered (the same constraint already existed for the burn-based design).
2. **mGLOBAL 7% refund leg**: refunded out-of-band "at the next monthly price update" — confirm destination address; it is not counted until received.
3. mGLOBAL cutoff day (26th) is unpublished — treat as ops parameter, monitor first real cohort.
4. Retired/paused Midas tokens (mFARM, mBTC, msyrupUSD, mevBTC) — keep or remove their accounts (out of scope here).

## 8. Future-proofing (proposal only, not implemented now)

New-issuer integrations decompose into three orthogonal axes; `common/` should eventually carry all three so a new issuer is ~20–30 lines:
1. **Attribution** — request-id set (extract the swap-and-pop loop used 6×), sub-account segregation (`SettlementSubAccount`, done here), or self-custodied position.
2. **Timing** — `CutoffPricer` covers rolling (period 0) and cohort schedules (done here).
3. **Pricing policy** — the only four observed across all 16 issuers: LIVE (Midas Comp), FROZEN_AT_REQUEST (mF-ONE, Superstate, GAIB), FROZEN_AT_CUTOFF (ACRED, mGLOBAL), MIN_QUOTE_LIVE (Makina). A policy enum inside the pricer would let future issuers pick a policy instead of writing valuation code.

Axes 1a/1c and the policy enum are deferred (YAGNI) — the documented pattern suffices until a third cutoff issuer appears.
