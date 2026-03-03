# UniversalDelegator Gas Report (Scenarios)

Date: 2026-03-03
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

## Without capture timestamp (captureTimestamp = 0)

Note: costs are lower because `latest()` state is used.

### Fully isolated and in different blocks

| Call | Request slash gas | Execute slash gas |
| --- | ---: | ---: |
| 1st | 316,951 ($0.07) | 563,143 ($0.12) |
| 2nd | 295,338 ($0.06) | 449,897 ($0.10) |

### Single transaction (not isolated, same block)

| Call | Request slash gas | Execute slash gas |
| --- | ---: | ---: |
| 1st | 295,450 ($0.06) | 608,477 ($0.13) |
| 2nd | 158,026 ($0.03) | 299,119 ($0.07) |

### Stake For Timestamp

| Call | Stake gas |
| --- | ---: |
| Before slashing | 155,083 ($0.03) |
| After slashing | 276,773 ($0.06) |

