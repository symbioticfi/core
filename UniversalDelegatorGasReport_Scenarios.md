# UniversalDelegator Gas Report (Scenarios)

Date: 2026-03-16
Command: `forge test --match-contract UniversalDelegatorGasTest -vvvvv --decode-internal --isolate`

3 subvaults, 3 networks in each, 10 operators in each
Operators to be slashed are first and second to maximize gas costs for slashing call

Notes:

- Different operators, same subvault/network.
- “Fully isolated” runs request1, request2, then execute1, execute2, with a block time jump between the phases.
- “Single transaction” uses two transactions: batch two requests, then batch two executes.
- “Stake For Timestamp” measures stakeForAt before any slashing and after the first slash (uses stakeFor when captureTimestamp = 0).
- “Without capture timestamp” passes captureTimestamp = 0 into requestSlash
- USD values show a 3-month average using baseFeePerGas samples (~30 samples over 90d) from Etherscan and ETH/USD from CoinGecko.

## Non-shared target (captureTimestamp = 0)

Note: costs are lower because `latest()` state is used.

### Fully isolated and in different blocks

| Call | Request slash gas | Execute slash gas |
| ---- | ----------------: | ----------------: |
| 1st  |   293,672 ($0.06) |   458,584 ($0.10) |
| 2nd  |   271,987 ($0.06) |   372,766 ($0.08) |

### Single transaction (not isolated, same block)

| Call | Request slash gas | Execute slash gas |
| ---- | ----------------: | ----------------: |
| 1st  |   272,081 ($0.06) |   503,918 ($0.11) |
| 2nd  |   146,657 ($0.03) |   227,988 ($0.05) |

### Stake For Timestamp

| Call            |       Stake gas |
| --------------- | --------------: |
| Before slashing | 131,810 ($0.03) |
| After slashing  | 153,090 ($0.03) |

## Shared-subvault target (captureTimestamp = 0)

Note: target operators live under a shared subvault; one of the three top-level subvaults is created with `isShared = true`.

### Fully isolated and in different blocks

| Call | Request slash gas | Execute slash gas |
| ---- | ----------------: | ----------------: |
| 1st  |   299,412 ($0.07) |   554,667 ($0.12) |
| 2nd  |   277,792 ($0.06) |   414,017 ($0.09) |

### Single transaction (not isolated, same block)

| Call | Request slash gas | Execute slash gas |
| ---- | ----------------: | ----------------: |
| 1st  |   277,903 ($0.06) |   599,470 ($0.13) |
| 2nd  |   148,479 ($0.03) |   259,108 ($0.06) |

### Stake For Timestamp

| Call            |       Stake gas |
| --------------- | --------------: |
| Before slashing | 120,791 ($0.03) |
| After slashing  | 146,635 ($0.03) |
