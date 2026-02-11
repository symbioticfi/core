# UniversalDelegator Gas Report (Second Operator After First Slash)

Date: 2026-02-03
Command: `forge test --match-contract UniversalDelegatorGasTest -vvvvv --decode-internal --isolate`

## Summary (same group/network, second operator)

| Call           | Hints |             Gas |
| -------------- | ----- | --------------: |
| `stakeForAt`   | no    | 169,038 ($0.04) |
| `stakeForAt`   | yes   | 169,038 ($0.04) |
| `requestSlash` | no    | 282,805 ($0.06) |
| `requestSlash` | yes   | 282,805 ($0.06) |
| `executeSlash` | no    | 562,209 ($0.12) |
| `executeSlash` | yes   | 562,209 ($0.12) |

Notes:

- Scenario: slash operator A (worst-case slot), then slash operator B in the **same** group/network.
- Operator B is the next operator slot in the same subnetwork (group=2, network=2, operatorIndex=8).
- “Hints” corresponds to the hints payload used by the test in `test/delegator/UniversalDelegatorGas.t.sol`.
- Gas values are from the test logs (console output).
- USD values are shown as a 3-month average using baseFeePerGas samples (~30 samples over 90d) from Etherscan and ETH/USD from CoinGecko.

## executeSlash components (no hints)

Immediate child calls of `UniversalSlasher::executeSlash` from the trace (inclusive per-call gas), for the **second** operator.

| Component                                            |             Gas | Notes                    |
| ---------------------------------------------------- | --------------: | ------------------------ |
| `ReentrancyGuardUpgradeable::_nonReentrantBefore`    |   5,089 ($0.00) | entry guard              |
| `UniversalSlasher::slashRequests`                    |  11,131 ($0.00) | load slash request       |
| `UniversalSlasher::_checkNetworkMiddleware`          |   5,623 ($0.00) | middleware check         |
| `VaultV2::epochDuration` (via proxy)                 |       0 ($0.00) | reads epoch duration     |
| `UniversalSlasher::slashableStake`                   | 278,494 ($0.06) | heavy path (read-only)   |
| `VaultV2::delegator` (via proxy)                     |   2,299 ($0.00) | delegator address lookup |
| `UniversalDelegator::onSlash`                        |  69,811 ($0.02) | delegator hook           |
| `VaultV2::delegator` (via proxy, for getIsNoPlugins) |   2,299 ($0.00) | delegator address lookup |
| `UniversalDelegator::getIsNoPlugins`                 |   2,257 ($0.00) | plugin mode check        |
| `VaultV2::onSlash` (via proxy)                       | 159,334 ($0.03) | vault accounting + burn  |
| `UniversalSlasher::_burnerOnSlash`                   |     165 ($0.00) | burner hook              |
| `ReentrancyGuardUpgradeable::_nonReentrantAfter`     |       0 ($0.00) | exit guard               |

## executeSlash components (with hints)

Immediate child calls of `UniversalSlasher::executeSlash` when hints are supplied (inclusive per-call gas), for the **second** operator.

| Component                                            |             Gas | Notes                             |
| ---------------------------------------------------- | --------------: | --------------------------------- |
| `ReentrancyGuardUpgradeable::_nonReentrantBefore`    |   5,089 ($0.00) | entry guard                       |
| `UniversalSlasher::slashRequests`                    |  11,131 ($0.00) | load slash request                |
| `UniversalSlasher::_checkNetworkMiddleware`          |   5,623 ($0.00) | middleware check                  |
| `VaultV2::epochDuration` (via proxy)                 |       0 ($0.00) | reads epoch duration              |
| `UniversalSlasher::slashableStake`                   | 278,494 ($0.06) | higher due to hint decoding/usage |
| `VaultV2::delegator` (via proxy)                     |   2,299 ($0.00) | delegator address lookup          |
| `UniversalDelegator::onSlash`                        |  69,811 ($0.02) | delegator hook                    |
| `VaultV2::delegator` (via proxy, for getIsNoPlugins) |   2,299 ($0.00) | delegator address lookup          |
| `UniversalDelegator::getIsNoPlugins`                 |   2,257 ($0.00) | plugin mode check                 |
| `VaultV2::onSlash` (via proxy)                       | 159,334 ($0.03) | vault accounting + burn           |
| `UniversalSlasher::_burnerOnSlash`                   |     165 ($0.00) | burner hook                       |
| `ReentrancyGuardUpgradeable::_nonReentrantAfter`     |       0 ($0.00) | exit guard                        |

## VaultV2::onSlash breakdown (after first slash)

Immediate child calls of `VaultV2::onSlash` (delegatecall) from the trace (inclusive per-call gas).
The breakdown is identical for the no-hints and with-hints runs in this test.

| Component                                         |            Gas | Notes               |
| ------------------------------------------------- | -------------: | ------------------- |
| `VaultV2::deallocatePlugins`                      |  2,148 ($0.00) | plugin deallocation |
| `ReentrancyGuardUpgradeable::_nonReentrantBefore` |  5,089 ($0.00) | entry guard         |
| `VaultV2Storage::activeStake`                     |    886 ($0.00) | read storage        |
| `VaultV2Storage::withdrawalBucket`                |    531 ($0.00) | read storage        |
| `Checkpoints::upperLookupRecent`                  |  2,718 ($0.00) | read checkpoint     |
| `Checkpoints::latest`                             |      0 ($0.00) | read checkpoint     |
| `VaultV2::activeWithdrawals`                      |  1,688 ($0.00) | aggregate read      |
| `VaultV2::activeWithdrawals`                      |  1,688 ($0.00) | aggregate read      |
| `VaultV2Storage::withdrawals`                     |  6,840 ($0.00) | read storage        |
| `Checkpoints::push`                               |  1,627 ($0.00) | write checkpoint    |
| `Checkpoints::push`                               |  1,627 ($0.00) | write checkpoint    |
| `VaultV2Storage::withdrawalShares`                |    840 ($0.00) | read storage        |
| `Checkpoints::push`                               | 47,728 ($0.01) | write checkpoint    |
| `Checkpoints::push`                               |  3,734 ($0.00) | write checkpoint    |
| `FixedPointMathLib::mulDiv`                       |     91 ($0.00) | math                |
| `Checkpoints::push`                               |  4,955 ($0.00) | write checkpoint    |
| `Checkpoints::push`                               | 47,725 ($0.01) | write checkpoint    |
| `VaultV2::_availableToSlash`                      | 10,748 ($0.00) | available balance   |
| `SafeTransferLib::safeTransfer`                   | 11,161 ($0.00) | transfer to burner  |
| `ReentrancyGuardUpgradeable::_nonReentrantAfter`  |      0 ($0.00) | exit guard          |

## Delta (with hints vs no hints)

| Component                          |     Δ Gas |
| ---------------------------------- | --------: |
| `UniversalSlasher::slashableStake` | 0 ($0.00) |
| Total `executeSlash`               | 0 ($0.00) |

## Caveats

- Component gas values are inclusive per call; they are **not additive**.
- The trace includes proxy layers; entries labeled “via proxy” reflect the proxy call cost plus the delegated implementation.
