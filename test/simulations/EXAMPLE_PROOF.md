> Amounts are shown in whole tokens (1 token = 1e18).
> Epoch duration: `3 days`.
> This file proves the current production shared-subvault logic is still invalid at the operator level.

## Core Bug

The current shared-subvault fix is network-scoped, not operator-scoped.

So:

1. a fresh network under a shared `subvault` does **not** inherit old shared slash credit
2. but a fresh operator inside an already-existing network **does** inherit that network’s preserved shared credit

That is wrong if the intended rule is:

- an operator that never had positive public `stakeFor()` must not become slashable from older shared credit

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

| Checkpoint | Public `stakeFor(A, alice, 0)` | Public `stakeFor(B, bob, 0)` | Public `stakeFor(B, charlie, 0)` | `slashableStake(B, bob, 0)` | `slashableStake(B, charlie, 0)` |
| --- | ---: | ---: | ---: | ---: | ---: |
| before slash on `A` | `10` | `0` | `-` | `10` | `-` |
| after slash on `A`, before `charlie` exists | `0` | `0` | `-` | `5` | `-` |
| after creating fresh `charlie(5)` | `0` | `0` | `0` | `5` | `5` |

## Why This Proves Invalidity

At the final checkpoint:

1. `charlie` has never had positive public `stakeFor()`
2. public `stakeFor(B, charlie, 0) = 0`
3. but `slashableStake(B, charlie, 0) = 5`

So the fresh operator inherits the existing network’s preserved shared credit.

That means the current shared-subvault logic is still missing an operator-level baseline.

## Pinned By

- `test_sharedSubvault_freshOperatorInExistingNetworkInheritsOldSharedSlashCredit`
