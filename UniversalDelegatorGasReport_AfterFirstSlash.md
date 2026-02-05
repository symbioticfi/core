# UniversalDelegator Gas Report (Second Operator After First Slash)

Date: 2026-02-03
Command: `forge test --match-contract UniversalDelegatorGasTest -vvvvv --decode-internal --isolate`

## Summary (same group/network, second operator)

| Call | Hints | Gas |
| --- | --- | ---: |
| `stakeForAt` | no | 269,019 ($0.06) |
| `stakeForAt` | yes | 269,019 ($0.06) |
| `requestSlash` | no | 289,698 ($0.06) |
| `requestSlash` | yes | 289,698 ($0.06) |
| `executeSlash` | no | 549,169 ($0.12) |
| `executeSlash` | yes | 549,169 ($0.12) |

Notes:
- Scenario: slash operator A (worst-case slot), then slash operator B in the **same** group/network.
- Operator B is the next operator slot in the same subnetwork (group=2, network=2, operatorIndex=8).
- “Hints” corresponds to the hints payload used by the test in `test/delegator/UniversalDelegatorGas.t.sol`.
- Gas values are from the test logs (console output).
- USD values are shown as a 3-month average using baseFeePerGas samples (~30 samples over 90d) from Etherscan and ETH/USD from CoinGecko.

## executeSlash components (no hints)

Immediate child calls of `UniversalSlasher::executeSlash` from the trace (inclusive per-call gas), for the **second** operator.

| Component | Gas | Notes |
| --- | ---: | --- |
| `ReentrancyGuardUpgradeable::_nonReentrantBefore` | 5,089 ($0.00) | entry guard |
| `UniversalSlasher::slashRequests` | 11,131 ($0.00) | load slash request |
| `UniversalSlasher::_checkNetworkMiddleware` | 5,623 ($0.00) | middleware check |
| `VaultV2::epochDuration` (via proxy) | 7,778 ($0.00) | reads epoch duration |
| `UniversalSlasher::slashableStake` | 242,869 ($0.05) | heavy path (read-only) |
| `VaultV2::delegator` (via proxy) | 2,233 ($0.00) | delegator address lookup |
| `UniversalDelegator::onSlash` | 94,253 ($0.02) | delegator hook |
| `VaultV2::onSlash` (via proxy) | 150,240 ($0.03) | vault accounting + burn |
| `UniversalSlasher::_burnerOnSlash` | 165 ($0.00) | burner hook |
| `ReentrancyGuardUpgradeable::_nonReentrantAfter` | 0 ($0.00) | exit guard |

## executeSlash components (with hints)

Immediate child calls of `UniversalSlasher::executeSlash` when hints are supplied (inclusive per-call gas), for the **second** operator.

| Component | Gas | Notes |
| --- | ---: | --- |
| `ReentrancyGuardUpgradeable::_nonReentrantBefore` | 5,089 ($0.00) | entry guard |
| `UniversalSlasher::slashRequests` | 11,131 ($0.00) | load slash request |
| `UniversalSlasher::_checkNetworkMiddleware` | 5,623 ($0.00) | middleware check |
| `VaultV2::epochDuration` (via proxy) | 7,778 ($0.00) | reads epoch duration |
| `UniversalSlasher::slashableStake` | 242,869 ($0.05) | higher due to hint decoding/usage |
| `VaultV2::delegator` (via proxy) | 2,233 ($0.00) | delegator address lookup |
| `UniversalDelegator::onSlash` | 94,253 ($0.02) | delegator hook |
| `VaultV2::onSlash` (via proxy) | 150,240 ($0.03) | vault accounting + burn |
| `UniversalSlasher::_burnerOnSlash` | 165 ($0.00) | burner hook |
| `ReentrancyGuardUpgradeable::_nonReentrantAfter` | 0 ($0.00) | exit guard |

## VaultV2::onSlash breakdown (after first slash)

Immediate child calls of `VaultV2::onSlash` (delegatecall) from the trace (inclusive per-call gas).
The breakdown is identical for the no-hints and with-hints runs in this test.

| Component | Gas | Notes |
| --- | ---: | --- |
| `ReentrancyGuardUpgradeable::_nonReentrantBefore` | 5,089 ($0.00) | entry guard |
| `Checkpoints::latest` | 494 ($0.00) | read checkpoint |
| `Checkpoints::latest` | 6,735 ($0.00) | read checkpoint |
| `Checkpoints::latest` | 735 ($0.00) | read checkpoint |
| `Checkpoints::upperLookupRecent` | 2,477 ($0.00) | read checkpoint |
| `Checkpoints::latest` | 261 ($0.00) | read checkpoint |
| `VaultV2Storage::activeStake` | 886 ($0.00) | read storage |
| `Checkpoints::push` | 3,734 ($0.00) | write checkpoint |
| `Checkpoints::push` | 1,621 ($0.00) | write checkpoint |
| `Checkpoints::push` | 1,621 ($0.00) | write checkpoint |
| `Checkpoints::push` | 47,722 ($0.01) | write checkpoint |
| `FixedPointMathLib::mulDiv` | 91 ($0.00) | math |
| `Checkpoints::push` | 4,949 ($0.00) | write checkpoint |
| `Checkpoints::push` | 47,725 ($0.01) | write checkpoint |
| `Token::balanceOf` | 2,625 ($0.00) | token read |
| `SafeTransferLib::safeTransfer` | 11,161 ($0.00) | transfer to burner |
| `ReentrancyGuardUpgradeable::_nonReentrantAfter` | 0 ($0.00) | exit guard |

## Delta (with hints vs no hints)

| Component | Δ Gas |
| --- | ---: |
| `UniversalSlasher::slashableStake` | 0 ($0.00) |
| Total `executeSlash` | 0 ($0.00) |

## Caveats

- Component gas values are inclusive per call; they are **not additive**.
- The trace includes proxy layers; entries labeled “via proxy” reflect the proxy call cost plus the delegated implementation.
