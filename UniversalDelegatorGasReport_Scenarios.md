# UniversalDelegator Gas Report (Scenarios)

Date: 2026-02-03
Command: `forge test --match-contract UniversalDelegatorGasTest -vvvvv --decode-internal --isolate`

Notes:
- Different operators, same group/network.
- “Fully isolated” runs two sequential slashes with a block time jump between them (intended to model separate txs).
- “Single transaction” executes both slashes inside one middleware call.
- “Without capture timestamp” passes `captureTimestamp = 0` into `requestSlash` (mapped to `block.timestamp - 4` for validity).
- USD values show a 3-month average using baseFeePerGas samples (~30 samples over 90d) from Etherscan and ETH/USD from CoinGecko.

## With capture timestamp

### Fully isolated and in different blocks

| Call | Stake gas | Request slash gas | Execute slash gas |
| --- | ---: | ---: | ---: |
| 1st | 132,364 ($0.03) | 336,329 ($0.07) | 787,178 ($0.17) |
| 2nd | 212,706 ($0.05) | 405,880 ($0.09) | 812,226 ($0.18) |

Note: 2nd call stake grows due to `prevSum` O(n) sloads; execute cost is slightly higher probably due to cumulative checkpoint growth

### Single transaction (not isolated, same block)

| Call | Stake gas | Request slash gas | Execute slash gas |
| --- | ---: | ---: | ---: |
| 1st | 130,252 ($0.03) | 226,588 ($0.05) | 648,207 ($0.14) |
| 2nd | 134,594 ($0.03) | 195,839 ($0.04) | 386,813 ($0.08) |

Note: 2nd call stake slightly grows due to `prevSum` O(n) sloads while warm slots; execute cost drops due to warm slots.

## Without capture timestamp (captureTimestamp = 0)

Note: costs are lower because `latest()` state is used.

### Fully isolated and in different blocks

| Call | Stake gas | Request slash gas | Execute slash gas |
| --- | ---: | ---: | ---: |
| 1st | 29,652 ($0.01) | 283,680 ($0.06) | 746,284 ($0.16) |
| 2nd | 29,637 ($0.01) | 341,891 ($0.07) | 755,992 ($0.16) |

Note: 2nd call stake grows due to `prevSum` O(n) sloads; execute cost is slightly higher probably due to cumulative checkpoint growth

### Single transaction (not isolated, same block)

| Call | Stake gas | Request slash gas | Execute slash gas |
| --- | ---: | ---: | ---: |
| 1st | 27,539 ($0.01) | 243,963 ($0.05) | 619,313 ($0.13) |
| 2nd | 7,524 ($0.00) | 221,874 ($0.05) | 346,578 ($0.08) |

Note: 2nd call stake slightly grows due to `prevSum` O(n) sloads while warm slots; execute cost drops due to warm slots.

