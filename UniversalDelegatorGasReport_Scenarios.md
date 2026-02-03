# UniversalDelegator Gas Report (Scenarios)

Date: 2026-02-03
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

| Call |       Stake gas | Request slash gas | Execute slash gas |
| ---- | --------------: | ----------------: | ----------------: |
| 1st  | 132,364 ($0.03) |   336,329 ($0.07) |   900,101 ($0.20) |
| 2nd  | 233,233 ($0.05) |   427,517 ($0.09) |   936,169 ($0.20) |

Note: 2nd call stake grows due to `prevSum` O(n) sloads; execute cost is slightly higher probably due to cumulative checkpoint growth

### Single transaction (not isolated, same block)

| Call |       Stake gas | Request slash gas | Execute slash gas |
| ---- | --------------: | ----------------: | ----------------: |
| 1st  | 130,252 ($0.03) |   226,588 ($0.05) |   761,130 ($0.17) |
| 2nd  | 159,121 ($0.03) |   201,476 ($0.04) |   394,582 ($0.09) |

Note: 2nd call stake slightly grows due to `prevSum` O(n) sloads while warm slots; execute cost drops due to warm slots.

## Without capture timestamp (captureTimestamp = 0)

Note: costs are lower because `latest()` state is used.

### Fully isolated and in different blocks

| Call |      Stake gas | Request slash gas | Execute slash gas |
| ---- | -------------: | ----------------: | ----------------: |
| 1st  | 29,652 ($0.01) |   283,680 ($0.06) |   859,207 ($0.19) |
| 2nd  | 29,637 ($0.01) |   357,069 ($0.08) |   869,476 ($0.19) |

Note: 2nd call stake grows due to `prevSum` O(n) sloads; execute cost is slightly higher probably due to cumulative checkpoint growth

### Single transaction (not isolated, same block)

| Call |      Stake gas | Request slash gas | Execute slash gas |
| ---- | -------------: | ----------------: | ----------------: |
| 1st  | 27,539 ($0.01) |   243,963 ($0.05) |   732,236 ($0.16) |
| 2nd  |  7,524 ($0.00) |   245,052 ($0.05) |   351,888 ($0.08) |

Note: 2nd call stake slightly grows due to `prevSum` O(n) sloads while warm slots; execute cost drops due to warm slots.
