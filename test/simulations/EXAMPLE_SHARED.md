> Amounts are shown in whole tokens (1 token = 1e18).
> Epoch duration: `3 days`.
> This file reflects the current production `UniversalDelegator` shared-subvault behavior.
> It shows the current contract as-is, including the remaining operator-level inheritance issue.

## Core Idea

Public `stakeFor()` is the real-time funded view.

Slasher `slashableStake()` can preserve shared guarantees inside a shared `subvault`, but the current production implementation is still mixed:

1. some sibling-preservation cases are working
2. fresh networks do not inherit old shared credit automatically
3. shared pending by itself does not create sibling-network guarantee
4. fresh operators inside existing shared sibling networks can still inherit old hidden credit
5. direct `onSlash()` on an unassigned operator still reverts with `ZeroIndex()`

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

| Checkpoint | `stakeFor(A, alice, 0)` | `stakeFor(B, bob, 0)` | `stakeFor(C, carol, 0)` | `slashableStake(B, bob, 0)` | Actual shared funds left | `executeSlash(B)` | `owed(B, bob)` |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| before first slash | `10` | `10` | `10` | `10` | `10` | `-` | `0` |
| after first slash on `A` | `0` | `0` | `10` | `10` | `0` | `-` | `0` |
| after second slash on `B` | `0` | `0` | `10` | `0` | `0` | `0` | `0` |

### Meaning

1. slashing `A` still preserves `B`'s requested slashability
2. executing the second slash on `B` no longer drains unrelated `carol` funds
3. the shared-overlap gap is not booked as `owed`

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

| Operator | Public `stakeFor(0)` | `slashableStake(0)` |
| --- | ---: | ---: |
| `bob` | `20` | `20` |
| `charlie` | `0` | `0` |

### Meaning

1. the fresh network starts from the current funded baseline
2. it does not inherit older shared size credit from before it existed

Pinned by:

- `test_sharedSubvault_freshNetworkDoesNotInheritOldSharedSlashCredit`

## Example 3: Fresh Operator Inside Existing Shared Network Still Inherits Old Hidden Credit

### Scenario

1. `create sharedSubvault(10)`
2. `create networkA(10) under sharedSubvault`
3. `create networkB(10) under sharedSubvault`
4. `create operator alice(10) under networkA`
5. `create operator bob(5) under networkB`
6. `deposit(10)`
7. `requestSlash(networkA, alice, 10)`
8. `executeSlash(networkA, alice, 10)`
9. `create operator charlie(5) under existing networkB`

### Checkpoint

| Operator | Public `stakeFor(0)` | `slashableStake(0)` |
| --- | ---: | ---: |
| `bob` | `0` | `5` |
| `charlie` | `0` | `5` |

### Meaning

1. `networkB` keeps hidden shared slashability after `A` is slashed
2. fresh `charlie` still becomes slashable even though his public `stakeFor()` is `0`
3. the old hidden guarantee is currently flowing through the network balance to later operators

Pinned by:

- `test_sharedSubvault_freshOperatorInExistingNetworkInheritsOldSharedSlashCredit`

## Example 4: Fresh Network After Shared Pending Keeps The Full Funded Shared Baseline

### Scenario

1. `create sharedSubvault(10)`
2. `create networkA(10) under sharedSubvault`
3. `create operator alice(10) under networkA`
4. `deposit(8)`
5. `wait(1s)`
6. `setSize(sharedSubvault, 5)` so the shared subtree now has:
   - durable size `5`
   - visible funded pending `3`
7. `create networkB(100) under sharedSubvault`
8. `create operator bob(100) under networkB`

### Checkpoints

| Value | Current actual |
| --- | ---: |
| `getAllocated(sharedSubvault, 0)` | `8` |
| `getPending(sharedSubvault, 0)` | `3` |
| public `stakeFor(B, bob, 0)` | `8` |
| `slashableStake(B, bob, 0)` | `8` |

### Meaning

1. the public path sees the full funded shared baseline `8`
2. the fresh network does not inherit older shared pending credit
3. shared pending by itself does not mint extra sibling guarantee, so slasher view stays at the funded baseline `8`

Sourced from:

- `test_sharedSubvault_freshNetworkAfterPendingSeesFundedBaselineForSlasher`

## Example 5: Shared Pending Alone Does Not Create Shared Guarantee For A Fresh Network

### Scenario

1. `create sharedSubvault(10)`
2. `create networkA(100) under sharedSubvault`
3. `create operator alice(100) under networkA`
4. `deposit(10)`
5. `wait(1s)`
6. `withdraw(4)`
7. `wait(99s)`
8. `setSize(sharedSubvault, 6)` creating old pending tranche `4`
9. `create networkB(100) under sharedSubvault`
10. `create operator bob(100) under networkB`
11. `wait(100s)`
12. `setSize(sharedSubvault, 2)` creating newer pending tranche `4`
13. `wait(epoch + 1s)` so the withdrawal is expired but both pending tranches are still in-window

### Checkpoints

| Value | Current actual |
| --- | ---: |
| `getAllocated(sharedSubvault, 0)` | `6` |
| `getPending(sharedSubvault, 0)` | `8` |
| public `stakeFor(B, bob, 0)` | `6` |
| `slashableStake(B, bob, 0)` | `6` |

### Meaning

1. shared pending still exists on the shared `subvault`
2. but because none of that pending has been consumed by slashing, it does not become sibling-network guarantee
3. the fresh network stays at the funded public baseline `6`

Sourced from:

- `test_simulation_sharedPendingDoesNotCreateSharedGuaranteeForFreshNetwork`

## Example 6: The Slashed Path Does Not Regain Its Own Shared-Size Effect After Regrowth

### Scenario

1. `create sharedSubvault(10)`
2. `create networkA(10) under sharedSubvault`
3. `create networkB(10) under sharedSubvault`
4. `create operator alice(10) under networkA`
5. `create operator bob(10) under networkB`
6. `deposit(10)`
7. `requestSlash(networkA, alice, 3)`
8. `executeSlash(networkA, alice, 3)`
9. `setSize(networkA, 10)`
10. `setSize(alice, 10)`

### Checkpoints

| Checkpoint | `stakeFor(A, alice, 0)` | `slashableStake(A, alice, 0)` | `slashableStake(B, bob, 0)` |
| --- | ---: | ---: | ---: |
| right after slash on `A` | `7` | `7` | `10` |
| after regrowing `A` and `alice` | `7` | `7` | `10` |

### Meaning

1. the slashed path does not regain public stake after regrowth
2. the slashed path also stays at `slashableStake = 7`
3. only the sibling keeps the preserved shared-size slashability at `10`

Sourced from:

- `test_sharedSubvault_slashedPathDoesNotRegainOwnSharedSizeGuaranteeAfterRegrowth`

## Example 7: Direct `onSlash()` On An Unassigned Operator Still Returns `ZeroIndex()`

### Scenario

1. call `delegator.onSlash(bytes32(0), address(0), 0, "")` directly from the slasher

### Checkpoint

| Value | Current actual |
| --- | ---: |
| revert data length | `4` |
| observed selector | `ZeroIndex()` |

### Meaning

1. direct `onSlash()` on an unassigned operator is still not returning `NotAssigned()`
2. the contract currently reverts earlier with `ZeroIndex()`

Sourced from:

- `test_onSlash_revertsNotAssigned`
