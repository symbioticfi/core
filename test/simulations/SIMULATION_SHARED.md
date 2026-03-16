> Amounts are shown in whole tokens (1 token = 1e18).
> Epoch duration: `3 days`.
> This document matches the current shared-slash behavior in `UniversalDelegatorCompactNew`.

## Scenario

1. `deposit(20)`
2. `createSlot(subvault, shared, 10)`
3. `createSlot(network1, parent=subvault, 10)`
4. `createSlot(operator1=alice, parent=network1, 10)`
5. `createSlot(network2, parent=subvault, 10)`
6. `createSlot(operator2=bob, parent=network2, 10)`
7. `slash(network1, alice, 10)`
8. `vault.onSlash(10)`
9. `wait(epoch + 1s)`

The slash is valid because `stakeFor(network1, alice, 0)` is `10` before the slash.

## Checkpoints

| Checkpoint                              | activeStake | subvault `size / slashPending / alloc(user) / alloc(slasher)` | network1 `size / slashPending / alloc(user) / alloc(slasher)` | operator1 `size / slashPending / alloc(user) / alloc(slasher)` | network2 `size / slashPending / alloc(user) / alloc(slasher)` | operator2 `size / slashPending / alloc(user) / alloc(slasher)` |
| --------------------------------------- | ----------- | ------------------------------------------------------------- | ------------------------------------------------------------- | -------------------------------------------------------------- | ------------------------------------------------------------- | -------------------------------------------------------------- |
| `t0` before slash                       | `20`        | `10 / 0 / 10 / 10`                                            | `10 / 0 / 10 / 10`                                            | `10 / 0 / 10 / 10`                                             | `10 / 0 / 10 / 10`                                            | `10 / 0 / 10 / 10`                                             |
| `t1` after `slash(network1, alice, 10)` | `10`        | `0 / 10 / 0 / 0`                                              | `0 / 10 / 0 / 0`                                              | `0 / 0 / 0 / 0`                                                | `10 / 0 / 0 / 10`                                             | `10 / 0 / 0 / 10`                                              |
| `t2` after `epoch + 1s`                 | `10`        | `0 / 10 / 0 / 0`                                              | `0 / 10 / 0 / 0`                                              | `0 / 0 / 0 / 0`                                                | `10 / 0 / 0 / 0`                                              | `10 / 0 / 0 / 0`                                               |

## Interpretation

1. `CompactNew` now models the shared path as `vault -> subvault -> network -> operator`.
2. A network/operator slash updates the shared subvault path and the slashed network path.
3. The mirrored sibling path is visible only to the slasher and only within one epoch.
4. After one epoch, the slasher-only sibling visibility expires while storage checkpoints remain in place.
