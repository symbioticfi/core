# UniversalDelegator Gas Report (Scenarios)

Date: 2026-02-04
Command: `forge test --match-contract UniversalDelegatorGasTest -vvvvv --decode-internal --isolate`

3 groups, 3 networks in each, 10 operators in each
Operators to be slashed are first and second to maximize gas costs for slashing call

Notes:
- Different operators, same group/network.
- “Fully isolated” runs two sequential slashes with a block time jump between them (2 txns)
- “Single transaction” executes both slashes inside one middleware call.
- “Without capture timestamp” passes captureTimestamp = 0 into requestSlash
- USD values show a 3-month average using baseFeePerGas samples (~30 samples over 90d) from Etherscan and ETH/USD from CoinGecko.

## With capture timestamp

### Fully isolated and in different blocks

| Call | Stake gas | Request slash gas | Execute slash gas |
| --- | ---: | ---: | ---: |
| 1st | 131,617 ($0.03) | 335,144 ($0.07) | 898,187 ($0.20) |
| 2nd | 231,672 ($0.05) | 425,444 ($0.09) | 933,367 ($0.20) |

Note: 2nd call stake grows due to `prevSum` O(n) sloads; execute cost is slightly higher probably due to cumulative checkpoint growth

### Single transaction (not isolated, same block)

| Call | Stake gas | Request slash gas | Execute slash gas |
| --- | ---: | ---: | ---: |
| 1st | 129,505 ($0.03) | 225,403 ($0.05) | 759,216 ($0.17) |
| 2nd | 157,560 ($0.03) | 199,403 ($0.04) | 391,780 ($0.09) |

Note: 2nd call stake slightly grows due to `prevSum` O(n) sloads while warm slots; execute cost drops due to warm slots.

## Without capture timestamp (captureTimestamp = 0)

Note: costs are lower because `latest()` state is used.

### Fully isolated and in different blocks

| Call | Stake gas | Request slash gas | Execute slash gas |
| --- | ---: | ---: | ---: |
| 1st | 29,652 ($0.01) | 282,924 ($0.06) | 857,638 ($0.19) |
| 2nd | 29,637 ($0.01) | 355,499 ($0.08) | 867,093 ($0.19) |

Note: 2nd call stake grows due to `prevSum` O(n) sloads; execute cost is slightly higher probably due to cumulative checkpoint growth

### Single transaction (not isolated, same block)

| Call | Stake gas | Request slash gas | Execute slash gas |
| --- | ---: | ---: | ---: |
| 1st | 27,539 ($0.01) | 243,207 ($0.05) | 730,667 ($0.16) |
| 2nd | 7,524 ($0.00) | 243,482 ($0.05) | 349,505 ($0.08) |

Note: 2nd call stake slightly grows due to `prevSum` O(n) sloads while warm slots; execute cost drops due to warm slots.

