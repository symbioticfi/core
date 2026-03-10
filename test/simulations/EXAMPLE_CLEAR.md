> Amounts are shown in whole tokens (1 token = 1e18).
> Epoch duration: `3 days`.
> This is the shared-slash behavior that matches the intended rule:
> public `stakeFor()` moves to real-time values, while `UniversalSlasher` can still slash unaffected sibling-network operators for their earlier guarantees.

## Scenario

1. `deposit(30)`
2. `createSlot(subvault, shared, 20)`
3. `createSlot(networkA, parent=subvault, 10)`
4. `createSlot(operatorA=alice, parent=networkA, 10)`
5. `createSlot(networkB, parent=subvault, 20)`
6. `createSlot(operatorB1=bob, parent=networkB, 10)`
7. `createSlot(operatorB2=charlie, parent=networkB, 10)`
8. `middleware.requestSlash(subnetworkA, alice, 10, 0, "")`
9. `middleware.executeSlash(slashIndexA, "")`

The slash is valid because before step `9`:

- `stakeFor(subnetworkA, alice, 0) = 10`

## Checkpoints

| Checkpoint | Public `stakeFor(A, alice, 0)` | Public `stakeFor(B, bob, 0)` | Public `stakeFor(B, charlie, 0)` | Slasher `stakeFor(B, bob, 0)` | Slasher `stakeFor(B, charlie, 0)` | `UniversalSlasher.slashableStake(B, bob, 0)` | `UniversalSlasher.slashableStake(B, charlie, 0)` |
| ---------- | ------------------------------ | ---------------------------- | -------------------------------- | ----------------------------- | --------------------------------- | --------------------------------------------- | ------------------------------------------------- |
| `t0` before slash | `10` | `10` | `10` | `10` | `10` | `10` | `10` |
| `t1` after slashing `A` | `0` | `10` | `0` | `10` | `10` | `10` | `10` |

## Why This Is The Right Shared-Clearing Behavior

After slashing `A`:

1. public `stakeFor()` already reflects new real-time shared availability
2. unaffected sibling-network operators in `B` are still slashable for their earlier provided guarantees
3. `UniversalSlasher` still sees both `bob` and `charlie` as slashable for `10`

That is the intended split:

1. public view = current real-time state
2. slasher path = preserved slash rights inside the epoch window

## Test

This behavior is pinned by:

- `test_sharedSubvault_firstSlash_preservesSiblingOperatorsSlashableStake_viaUniversalSlasher`
