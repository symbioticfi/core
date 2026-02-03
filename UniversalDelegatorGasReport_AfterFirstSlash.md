# UniversalDelegator Gas Report (Second Operator After First Slash)

Date: 2026-02-03
Command: `forge test --match-contract UniversalDelegatorGasTest -vvvvv --decode-internal --isolate`

## Summary (same group/network, second operator)

| Call | Hints | Gas |
| --- | --- | ---: |
| `stakeForAt` | no | 212,706 |
| `stakeForAt` | yes | 212,706 |
| `requestSlash` | no | 405,880 |
| `requestSlash` | yes | 405,880 |
| `executeSlash` | no | 812,226 |
| `executeSlash` | yes | 812,226 |

Notes:
- Scenario: slash operator A (worst-case slot), then slash operator B in the **same** group/network.
- Operator B is the next operator slot in the same subnetwork (group=2, network=2, operatorIndex=8).
- “Hints” corresponds to the hints payload used by the test in `test/delegator/UniversalDelegatorGas.t.sol`.
- Gas values are from the test logs (console output).

## executeSlash components (no hints)

Immediate child calls of `UniversalSlasher::executeSlash` from the trace (inclusive per-call gas), for the **second** operator.

| Component | Gas | Notes |
| --- | ---: | --- |
| `ReentrancyGuardUpgradeable::_nonReentrantBefore` | 5,081 | entry guard |
| `UniversalSlasher::slashRequests` | 11,131 | load slash request |
| `UniversalSlasher::_checkNetworkMiddleware` | 5,569 | middleware check |
| `VaultV2::epochDuration` (via proxy) | 7,400 | reads epoch duration |
| `UniversalSlasher::_slashableStake` | 251,471 | heavy path (read-only) |
| `UniversalSlasher::cumulativeSlash` | 635 | read checkpoint |
| `Checkpoints::push` | 65,621 | cumulative slash checkpoint write |
| `UniversalSlasher::groupCumulativeSlash` | 861 | read checkpoint |
| `Checkpoints::push` | 49,708 | group cumulative checkpoint write |
| `VaultV2::onSlash` (via proxy) | 284,022 | vault accounting + burn |
| `VaultV2::delegator` (via proxy) | 906 | delegator address lookup |
| `UniversalDelegator::onSlash` | 79,214 | delegator hook |
| `UniversalSlasher::_burnerOnSlash` | 167 | burner hook |
| `ReentrancyGuardUpgradeable::_nonReentrantAfter` | 0 | exit guard |

## executeSlash components (with hints)

Immediate child calls of `UniversalSlasher::executeSlash` when hints are supplied (inclusive per-call gas), for the **second** operator.

| Component | Gas | Notes |
| --- | ---: | --- |
| `ReentrancyGuardUpgradeable::_nonReentrantBefore` | 5,081 | entry guard |
| `UniversalSlasher::slashRequests` | 11,131 | load slash request |
| `UniversalSlasher::_checkNetworkMiddleware` | 5,569 | middleware check |
| `VaultV2::epochDuration` (via proxy) | 7,400 | reads epoch duration |
| `UniversalSlasher::_slashableStake` | 251,471 | higher due to hint decoding/usage |
| `UniversalSlasher::cumulativeSlash` | 635 | read checkpoint |
| `Checkpoints::push` | 65,621 | cumulative slash checkpoint write |
| `UniversalSlasher::groupCumulativeSlash` | 861 | read checkpoint |
| `Checkpoints::push` | 49,708 | group cumulative checkpoint write |
| `VaultV2::onSlash` (via proxy) | 284,022 | vault accounting + burn |
| `VaultV2::delegator` (via proxy) | 906 | delegator address lookup |
| `UniversalDelegator::onSlash` | 79,214 | delegator hook |
| `UniversalSlasher::_burnerOnSlash` | 167 | burner hook |
| `ReentrancyGuardUpgradeable::_nonReentrantAfter` | 0 | exit guard |

## VaultV2::onSlash breakdown (after first slash)

Immediate child calls of `VaultV2::onSlash` (delegatecall) from the trace (inclusive per-call gas).
The breakdown is identical for the no-hints and with-hints runs in this test.

| Component | Gas | Notes |
| --- | ---: | --- |
| `ReentrancyGuardUpgradeable::_nonReentrantBefore` | 5,052 | entry guard |
| `Checkpoints::latest` | 494 | read checkpoint |
| `Checkpoints::latest` | 6,735 | read checkpoint |
| `Checkpoints::latest` | 6,735 | read checkpoint |
| `Checkpoints::upperLookupRecent` | 2,477 | read checkpoint |
| `Checkpoints::latest` | 261 | read checkpoint |
| `VaultV2Storage::activeStake` | 2,886 | read storage |
| `Checkpoints::push` | 25,997 | write checkpoint |
| `Checkpoints::push` | 29,812 | write checkpoint |
| `Checkpoints::push` | 29,812 | write checkpoint |
| `Checkpoints::push` | 47,725 | write checkpoint |
| `FixedPointMathLib::mulDiv` | 91 | math |
| `Checkpoints::push` | 52,944 | write checkpoint |
| `Checkpoints::push` | 47,725 | write checkpoint |
| `Token::balanceOf` | 2,559 | token read |
| `SafeTransferLib::safeTransfer` | 11,095 | transfer to burner |
| `ReentrancyGuardUpgradeable::_nonReentrantAfter` | 0 | exit guard |

## Delta (with hints vs no hints)

| Component | Δ Gas |
| --- | ---: |
| `UniversalSlasher::_slashableStake` | 0 |
| Total `executeSlash` | 0 |

## Caveats

- Component gas values are inclusive per call; they are **not additive**.
- The trace includes proxy layers; entries labeled “via proxy” reflect the proxy call cost plus the delegated implementation.
