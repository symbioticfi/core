# UniversalDelegator Gas Report

Date: 2026-02-03
Command: `forge test --match-contract UniversalDelegatorGasTest -vvvvv --decode-internal --isolate`

## Summary (worst-case position)

| Call | Hints | Gas |
| --- | --- | ---: |
| `stakeForAt` | no | 148,917 |
| `stakeForAt` | yes | 163,146 |
| `executeSlash` | no | 967,369 |
| `executeSlash` | yes | 1,006,191 |

Notes:
- Worst-case operator/network/group position with 3 groups × 3 networks × 10 operators.
- “Hints” corresponds to the hints payload used by the test in `test/delegator/UniversalDelegatorGas.t.sol`.
- Gas values are from the test logs (console output).

## executeSlash components (no hints)

These are immediate child calls of `UniversalSlasher::executeSlash` from the trace (inclusive per-call gas).

| Component | Gas | Notes |
| --- | ---: | --- |
| `ReentrancyGuardUpgradeable::_nonReentrantBefore` | 5,089 | entry guard |
| `UniversalSlasher::slashRequests` | 11,131 | load slash request |
| `UniversalSlasher::_checkNetworkMiddleware` | 5,623 | middleware check |
| `VaultV2::epochDuration` (via proxy) | 7,778 | reads epoch duration |
| `UniversalSlasher::_slashableStake` | 187,854 | heavy path (read-only) |
| `UniversalSlasher::cumulativeSlash` | 635 | read checkpoint |
| `Checkpoints::push` | 90,332 | cumulative slash checkpoint write |
| `UniversalSlasher::groupCumulativeSlash` | 387 | read checkpoint |
| `Checkpoints::push` | 90,332 | group cumulative checkpoint write |
| `VaultV2::onSlash` (via proxy) | 436,104 | vault accounting + burn |
| `VaultV2::delegator` (via proxy) | 2,233 | delegator address lookup |
| `UniversalDelegator::onSlash` | 78,998 | delegator hook |
| `UniversalSlasher::_burnerOnSlash` | 167 | burner hook |
| `ReentrancyGuardUpgradeable::_nonReentrantAfter` | 0 | exit guard |

## executeSlash components (with hints)

Immediate child calls of `UniversalSlasher::executeSlash` when hints are supplied (inclusive per-call gas).

| Component | Gas | Notes |
| --- | ---: | --- |
| `ReentrancyGuardUpgradeable::_nonReentrantBefore` | 5,089 | entry guard |
| `UniversalSlasher::slashRequests` | 11,131 | load slash request |
| `UniversalSlasher::_checkNetworkMiddleware` | 5,623 | middleware check |
| `VaultV2::epochDuration` (via proxy) | 7,778 | reads epoch duration |
| `UniversalSlasher::_slashableStake` | 209,534 | higher due to hint decoding/usage |
| `UniversalSlasher::cumulativeSlash` | 635 | read checkpoint |
| `Checkpoints::push` | 90,332 | cumulative slash checkpoint write |
| `UniversalSlasher::groupCumulativeSlash` | 387 | read checkpoint |
| `Checkpoints::push` | 90,332 | group cumulative checkpoint write |
| `VaultV2::onSlash` (via proxy) | 436,104 | vault accounting + burn |
| `VaultV2::delegator` (via proxy) | 2,233 | delegator address lookup |
| `UniversalDelegator::onSlash` | 78,998 | delegator hook |
| `UniversalSlasher::_burnerOnSlash` | 167 | burner hook |
| `ReentrancyGuardUpgradeable::_nonReentrantAfter` | 0 | exit guard |

## VaultV2::onSlash breakdown

Immediate child calls of `VaultV2::onSlash` (delegatecall) from the trace (inclusive per-call gas).
The breakdown is identical for the no-hints and with-hints runs in this test.

| Component | Gas | Notes |
| --- | ---: | --- |
| `ReentrancyGuardUpgradeable::_nonReentrantBefore` | 5,089 | entry guard |
| `Checkpoints::latest` | 198 | read checkpoint |
| `Checkpoints::latest` | 2,261 | read checkpoint |
| `Checkpoints::latest` | 261 | read checkpoint |
| `Checkpoints::upperLookupRecent` | 2,477 | read checkpoint |
| `Checkpoints::latest` | 261 | read checkpoint |
| `VaultV2Storage::activeStake` | 886 | read storage |
| `Checkpoints::push` | 42,708 | write checkpoint |
| `Checkpoints::push` | 70,432 | write checkpoint |
| `Checkpoints::push` | 70,432 | write checkpoint |
| `Checkpoints::push` | 72,432 | write checkpoint |
| `FixedPointMathLib::mulDiv` | 91 | math |
| `Checkpoints::push` | 52,944 | write checkpoint |
| `Checkpoints::push` | 72,432 | write checkpoint |
| `Token::balanceOf` | 2,625 | token read |
| `SafeTransferLib::safeTransfer` | 28,261 | transfer to burner |
| `ReentrancyGuardUpgradeable::_nonReentrantAfter` | 0 | exit guard |

## Delta (with hints vs no hints)

| Component | Δ Gas |
| --- | ---: |
| `UniversalSlasher::_slashableStake` | +21,680 |
| Total `executeSlash` | +38,822 |

## Caveats

- Component gas values are inclusive per call; they are **not additive**.
- The trace includes proxy layers; entries labeled “via proxy” reflect the proxy call cost plus the delegated implementation.
