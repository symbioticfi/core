# UniversalDelegator Gas Report (Scenarios)

Date: 2026-02-04
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
| 1st | 315,985 ($0.07) | 742,954 ($0.16) |
| 2nd | 294,372 ($0.06) | 546,865 ($0.12) |

### Single transaction (not isolated, same block)

| Call | Request slash gas | Execute slash gas |
| --- | ---: | ---: |
| 1st | 294,484 ($0.06) | 732,301 ($0.16) |
| 2nd | 171,060 ($0.04) | 393,385 ($0.09) |

### Stake For Timestamp

| Call | Stake gas |
| --- | ---: |
| Before slashing | 152,568 ($0.03) |
| After slashing | 242,466 ($0.05) |

