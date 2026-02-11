# UniversalDelegator Gas Report (Scenarios)

Date: 2026-02-11
Command: `forge test --match-contract UniversalDelegatorGasTest -vvvvv --decode-internal --isolate`

3 groups, 3 networks in each, 10 operators in each
Operators to be slashed are first and second to maximize gas costs for slashing call

Notes:
- Different operators, same group/network.
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
| 1st | 296,553 ($0.06) | 772,328 ($0.17) |
| 2nd | 274,940 ($0.06) | 545,463 ($0.12) |

### Single transaction (not isolated, same block)

| Call | Request slash gas | Execute slash gas |
| --- | ---: | ---: |
| 1st | 275,052 ($0.06) | 761,675 ($0.17) |
| 2nd | 153,628 ($0.03) | 385,983 ($0.08) |

### Stake For Timestamp

| Call | Stake gas |
| --- | ---: |
| Before slashing | 134,685 ($0.03) |
| After slashing | 263,145 ($0.06) |

