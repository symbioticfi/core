> Amounts are shown in whole tokens (1 token = 1e18).
> Epoch duration: `3 days`.
> This file reflects the current production `UniversalDelegator` shared-subvault slashing behavior.
> It shows the current intended production behavior after the shared-subvault settlement fix.

## Core Idea

Public `stakeFor()` remains real-time actual.

Slasher `slashableStake()` is still determined from current `stakeFor(..., 0)`, but for networks under a shared `subvault` it preserves sibling-network guarantees through network-scoped shared consumed traces:

1. `sharedPendingConsumedCursor`
2. `sharedSizeConsumedCumulative`

So:

1. slashing `network A` does not reduce `slashableStake()` of sibling `network B`
2. a fresh network does not inherit old shared slash credit
3. pending-based sibling preservation lasts only until the original pending expiry

## Example 1: Sibling Slashable Stake Is Preserved, And Second Execution Settles Zero

### Scenario

1. `create sharedSubvault(10)`
2. `create isolatedSubvault(10)`
3. `create networkA(10) under sharedSubvault`
4. `create networkB(10) under sharedSubvault`
5. `create operator alice(10) under networkA`
6. `create operator bob(10) under networkB`
7. `create networkC(10) under isolatedSubvault`
8. `create operator carol(10) under networkC`
9. `deposit(20)`
10. `requestSlash(networkA, alice, 10)`
11. `requestSlash(networkB, bob, 10)`
12. `executeSlash(networkA, alice, 10)`
13. `executeSlash(networkB, bob, 10)`

### Checkpoints


| Checkpoint                | `stakeFor(A, alice, 0)` | `stakeFor(B, bob, 0)` | `stakeFor(C, carol, 0)` | `slashableStake(B, bob, 0)` | Actual shared funds left | `executeSlash(B)` | `owed(B, bob)` |
| ------------------------- | ----------------------- | --------------------- | ----------------------- | --------------------------- | ------------------------ | ---------------- | -------------- |
| before first slash        | `10`                    | `10`                  | `10`                    | `10`                        | `10`                     | `-`              | `0`            |
| after first slash on `A`  | `0`                     | `0`                   | `10`                    | `10`                        | `0`                      | `-`              | `0`            |
| after second slash on `B` | `0`                     | `0`                   | `10`                    | `0`                         | `0`                      | `0`              | `0`            |


### Meaning

1. Public view after slashing `A`: `bob` is `0`
2. Slasher view after slashing `A`: `bob` is still slashable for `10`
3. The shared `subvault` had only `10`, so after slashing `A` there are no shared funds left for `B`
4. Executing the second slash on `B` does not drain unrelated `carol` funds anymore
5. The second slash settles `0` and does not create `owed`, because the shared-overlap gap is not vault debt

Pinned by:

- `test_sharedSubvault_firstSlashDoesNotReduceSiblingSlashableStake`

## Example 2: Fresh Network Does Not Inherit Old Shared Slash Credit

### Scenario

1. `create sharedSubvault(100)`
2. `create networkA(100) under sharedSubvault`
3. `create operator alice(100) under networkA`
4. `deposit(100)`
5. `requestSlash(networkA, alice, 80)`
6. `executeSlash(networkA, alice, 80)`
7. `create networkB(100) under sharedSubvault`
8. `create operator bob(50) under networkB`
9. `create operator charlie(50) under networkB`

### Checkpoint


| Operator  | Public `stakeFor(0)` | `slashableStake(0)` |
| --------- | -------------------- | ------------------- |
| `bob`     | `20`                 | `20`                |
| `charlie` | `0`                  | `0`                 |


### Meaning

1. The fresh network gets only what is currently funded
2. It does not inherit the old shared slash credit from before it existed
3. So `charlie` cannot be newly slashable just because `alice` was slashed earlier

Pinned by:

- `test_sharedSubvault_freshNetworkDoesNotInheritOldSharedSlashCredit`

## Example 3: Pending Slash Preserves Sibling Slashable Stake Until Expiry

### Scenario

1. `create sharedSubvault(10)`
2. `create networkA(10) under sharedSubvault`
3. `create networkB(10) under sharedSubvault`
4. `create operator alice(10) under networkA`
5. `create operator bob(10) under networkB`
6. `deposit(10)`
7. `wait(1s)`
8. `setSize(sharedSubvault, 0)` to move all shared policy into pending
9. `requestSlash(networkA, alice, 10)`
10. `executeSlash(networkA, alice, 10)`
11. `wait(epoch + 1s)`

### Checkpoints


| Checkpoint           | Public `stakeFor(B, bob, 0)` | `slashableStake(B, bob, 0)` |
| -------------------- | ---------------------------- | --------------------------- |
| before slash on `A`  | `10`                         | `10`                        |
| after slash on `A`   | `0`                          | `10`                        |
| after pending expiry | `0`                          | `0`                         |


### Meaning

1. Shared pending guarantee is preserved for sibling `B` during the original pending window
2. That preserved slashability disappears when the original pending expires
3. It is not extended indefinitely

Pinned by:

- `test_sharedSubvault_pendingSlashDoesNotReduceSiblingSlashableStakeUntilExpiry`
