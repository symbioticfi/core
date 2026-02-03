# UniversalDelegator Gas Report (Scenarios)

Date: 2026-02-03
Command: `forge test --match-contract UniversalDelegatorGasTest -vvvvv --decode-internal --isolate`

Notes:
- Different operators, same group/network.
- “Fully isolated” runs two sequential slashes with a block time jump between them (intended to model separate txs).
- “Single transaction” executes both slashes inside one middleware call.
- “Without capture timestamp” passes `captureTimestamp = 0` into `requestSlash` (mapped to `block.timestamp - 4` for validity).

## With capture timestamp

### Fully isolated and in different blocks

| Call | Stake gas | Request slash gas | Execute slash gas |
| --- | ---: | ---: | ---: |
| 1st | 132,364 | 336,329 | 787,178 |
| 2nd | 212,706 | 405,880 | 812,226 |

Note: 2nd call stake grows due to `prevSum` O(n) sloads; execute cost is slightly higher probably due to cumulative checkpoint growth

### Single transaction (not isolated, same block)

| Call | Stake gas | Request slash gas | Execute slash gas |
| --- | ---: | ---: | ---: |
| 1st | 130,252 | 226,588 | 648,207 |
| 2nd | 134,594 | 195,839 | 386,813 |

Note: 2nd call stake slightly grows due to `prevSum` O(n) sloads while warm slots; execute cost drops due to warm slots.

## Without capture timestamp (captureTimestamp = 0)

Note: costs are lower because `latest()` state is used.

### Fully isolated and in different blocks

| Call | Stake gas | Request slash gas | Execute slash gas |
| --- | ---: | ---: | ---: |
| 1st | 29,652 | 283,680 | 746,284 |
| 2nd | 29,637 | 341,891 | 755,992 |

Note: 2nd call stake grows due to `prevSum` O(n) sloads; execute cost is slightly higher probably due to cumulative checkpoint growth

### Single transaction (not isolated, same block)

| Call | Stake gas | Request slash gas | Execute slash gas |
| --- | ---: | ---: | ---: |
| 1st | 27,539 | 243,963 | 619,313 |
| 2nd | 7,524 | 221,874 | 346,578 |

Note: 2nd call stake slightly grows due to `prevSum` O(n) sloads while warm slots; execute cost drops due to warm slots.

