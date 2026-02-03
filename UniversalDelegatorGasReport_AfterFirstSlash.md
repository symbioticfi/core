# UniversalDelegator Gas Report (Second Operator After First Slash)

Date: 2026-02-03
Command: `forge test --match-contract UniversalDelegatorGasTest -vvvvv --decode-internal --isolate`

## Summary (same group/network, second operator)

| Call | Hints | Gas |
| --- | --- | ---: |
| `stakeForAt` | no | 218,837 |
| `stakeForAt` | yes | 221,120 |
| `executeSlash` | no | 658,633 |
| `executeSlash` | yes | 668,911 |

Notes:
- Scenario: slash operator A (worst-case slot), then slash operator B in the **same** group/network.
- Operator B is the next operator slot in the same subnetwork (group=2, network=2, operatorIndex=8).
- “Hints” corresponds to the hints payload used by the test in `test/delegator/UniversalDelegatorGas.t.sol`.
- Gas values are from the test logs (console output).

## executeSlash components (no hints)

Immediate child calls of `UniversalSlasher::executeSlash` from the trace (inclusive per-call gas), for the **second** operator.

| Component | Gas | Notes |
| --- | ---: | --- |
| `ReentrancyGuardUpgradeable::_nonReentrantBefore` | 5,089 | entry guard |
| `UniversalSlasher::slashRequests` | 11,131 | load slash request |
| `UniversalSlasher::_checkNetworkMiddleware` | 5,623 | middleware check |
| `VaultV2::epochDuration` (via proxy) | 7,778 | reads epoch duration |
| `UniversalSlasher::_slashableStake` | 263,983 | heavy path (read-only) |
| `UniversalSlasher::cumulativeSlash` | 635 | read checkpoint |
| `Checkpoints::push` | 65,621 | cumulative slash checkpoint write |
| `UniversalSlasher::groupCumulativeSlash` | 861 | read checkpoint |
| `Checkpoints::push` | 4,427 | group cumulative checkpoint write |
| `VaultV2::onSlash` (via proxy) | 158,240 | vault accounting + burn |
| `VaultV2::delegator` (via proxy) | 2,233 | delegator address lookup |
| `UniversalDelegator::onSlash` | 82,129 | delegator hook |
| `UniversalSlasher::_burnerOnSlash` | 167 | burner hook |
| `ReentrancyGuardUpgradeable::_nonReentrantAfter` | 0 | exit guard |

## executeSlash components (with hints)

Immediate child calls of `UniversalSlasher::executeSlash` when hints are supplied (inclusive per-call gas), for the **second** operator.

| Component | Gas | Notes |
| --- | ---: | --- |
| `ReentrancyGuardUpgradeable::_nonReentrantBefore` | 5,089 | entry guard |
| `UniversalSlasher::slashRequests` | 11,131 | load slash request |
| `UniversalSlasher::_checkNetworkMiddleware` | 5,623 | middleware check |
| `VaultV2::epochDuration` (via proxy) | 7,778 | reads epoch duration |
| `UniversalSlasher::_slashableStake` | 268,975 | higher due to hint decoding/usage |
| `UniversalSlasher::cumulativeSlash` | 635 | read checkpoint |
| `Checkpoints::push` | 65,621 | cumulative slash checkpoint write |
| `UniversalSlasher::groupCumulativeSlash` | 861 | read checkpoint |
| `Checkpoints::push` | 4,427 | group cumulative checkpoint write |
| `VaultV2::onSlash` (via proxy) | 158,240 | vault accounting + burn |
| `VaultV2::delegator` (via proxy) | 2,233 | delegator address lookup |
| `UniversalDelegator::onSlash` | 82,129 | delegator hook |
| `UniversalSlasher::_burnerOnSlash` | 167 | burner hook |
| `ReentrancyGuardUpgradeable::_nonReentrantAfter` | 0 | exit guard |

## VaultV2::onSlash breakdown (after first slash)

Immediate child calls of `VaultV2::onSlash` (delegatecall) from the trace (inclusive per-call gas).
The breakdown is identical for the no-hints and with-hints runs in this test.

| Component | Gas | Notes |
| --- | ---: | --- |
| `ReentrancyGuardUpgradeable::_nonReentrantBefore` | 5,089 | entry guard |
| `Checkpoints::latest` | 494 | read checkpoint |
| `Checkpoints::latest` | 6,735 | read checkpoint |
| `Checkpoints::latest` | 6,735 | read checkpoint |
| `Checkpoints::upperLookupRecent` | 2,477 | read checkpoint |
| `Checkpoints::latest` | 261 | read checkpoint |
| `VaultV2Storage::activeStake` | 2,886 | read storage |
| `Checkpoints::push` | 3,734 | write checkpoint |
| `Checkpoints::push` | 1,621 | write checkpoint |
| `Checkpoints::push` | 1,621 | write checkpoint |
| `Checkpoints::push` | 47,722 | write checkpoint |
| `FixedPointMathLib::mulDiv` | 91 | math |
| `Checkpoints::push` | 4,949 | write checkpoint |
| `Checkpoints::push` | 47,725 | write checkpoint |
| `Token::balanceOf` | 2,625 | token read |
| `SafeTransferLib::safeTransfer` | 11,161 | transfer to burner |
| `ReentrancyGuardUpgradeable::_nonReentrantAfter` | 0 | exit guard |

## Delta (with hints vs no hints)

| Component | Δ Gas |
| --- | ---: |
| `UniversalSlasher::_slashableStake` | 4,992 |
| Total `executeSlash` | 10,278 |

## Caveats

- Component gas values are inclusive per call; they are **not additive**.
- The trace includes proxy layers; entries labeled “via proxy” reflect the proxy call cost plus the delegated implementation.
