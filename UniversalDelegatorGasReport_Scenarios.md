# UniversalDelegator Gas Report (Scenarios)

Date: 2026-02-05
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
| 1st | 297,268 ($0.06) | 649,350 ($0.14) |
| 2nd | 275,655 ($0.06) | 488,653 ($0.11) |

### Single transaction (not isolated, same block)

| Call | Request slash gas | Execute slash gas |
| --- | ---: | ---: |
| 1st | 275,767 ($0.06) | 638,697 ($0.14) |
| 2nd | 160,343 ($0.03) | 343,173 ($0.07) |

### Stake For Timestamp

| Call | Stake gas |
| --- | ---: |
| Before slashing | 133,851 ($0.03) |
| After slashing | 213,099 ($0.05) |

