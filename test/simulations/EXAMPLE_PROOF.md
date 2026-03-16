> Amounts are shown in whole tokens (1 token = 1e18).
> Epoch duration: `3 days`.
> This file shows the current operator-level behavior for shared subvault slash preservation.

## Core Rule

For a shared `subvault`:

1. an existing sibling network keeps its preserved slashability
2. a fresh network does not inherit older shared credit
3. a fresh operator inside an already-existing sibling network can still inherit older shared credit

## Scenario

1. `create sharedSubvault(10)`
2. `create networkA(10) under sharedSubvault`
3. `create networkB(10) under sharedSubvault`
4. `create alice(10) under networkA`
5. `create bob(5) under networkB`
6. `deposit(10)`
7. `requestSlash(networkA, alice, 10)`
8. `executeSlash(networkA, alice, 10)`
9. `create charlie(5) under existing networkB`

## Checkpoints

| Checkpoint                                  | Public `stakeFor(A, alice, 0)` | Public `stakeFor(B, bob, 0)` | Public `stakeFor(B, charlie, 0)` | `slashableStake(B, bob, 0)` | `slashableStake(B, charlie, 0)` |
| ------------------------------------------- | -----------------------------: | ---------------------------: | -------------------------------: | --------------------------: | ------------------------------: |
| before slash on `A`                         |                           `10` |                          `0` |                              `-` |                        `10` |                             `-` |
| after slash on `A`, before `charlie` exists |                            `0` |                          `0` |                              `-` |                         `5` |                             `-` |
| after creating fresh `charlie(5)`           |                            `0` |                          `0` |                              `0` |                         `5` |                             `5` |

## Why This Is Correct

At the final checkpoint:

1. `bob` keeps the preserved shared slashability of the already-existing sibling path
2. `charlie` never had positive public `stakeFor()`
3. `charlie` still becomes slashable because the old hidden network-level guarantee flows through `networkB`

So the current code still needs operator handling if this inheritance is not intended.

## Pinned By

- `test_sharedSubvault_freshOperatorInExistingNetworkInheritsOldSharedSlashCredit`
