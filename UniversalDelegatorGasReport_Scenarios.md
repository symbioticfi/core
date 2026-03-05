# UniversalDelegator Gas Report (Scenarios)

Date: 2026-03-05
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
| 1st | 293,254 ($0.06) | 451,435 ($0.10) |
| 2nd | 271,611 ($0.06) | 365,660 ($0.08) |

### Single transaction (not isolated, same block)

| Call | Request slash gas | Execute slash gas |
| --- | ---: | ---: |
| 1st | 271,717 ($0.06) | 496,769 ($0.11) |
| 2nd | 146,293 ($0.03) | 224,882 ($0.05) |

### Stake For Timestamp

| Call | Stake gas |
| --- | ---: |
| Before slashing | 131,404 ($0.03) |
| After slashing | 152,726 ($0.03) |

