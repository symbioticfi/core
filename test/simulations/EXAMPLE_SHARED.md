> Amounts are shown in whole tokens (1 token = 1e18).
> Epoch duration: `3 days`.
> This is a valid shared-subvault under-slashing witness against the current `CompactNew` logic.

## Scenario

1. `deposit(30)`
2. `createSlot(subvault, shared, 20)`
3. `createSlot(networkA, parent=subvault, 10)`
4. `createSlot(operatorA=alice, parent=networkA, 10)`
5. `createSlot(networkB, parent=subvault, 20)`
6. `createSlot(operatorB1=bob, parent=networkB, 10)`
7. `createSlot(operatorB2=charlie, parent=networkB, 10)`
8. `middleware.requestSlash(subnetworkA, alice, 10, 0, "")`
9. wait `2s`
10. `middleware.executeSlash(slashIndexA, "")`
11. wait `epoch - 2s`
12. `middleware.requestSlash(subnetworkB, charlie, 10, 0, "")`
13. wait `3s`
14. `middleware.executeSlash(slashIndexB, "")`

## Checkpoints

| Checkpoint | Public `stakeFor(B, charlie, 0)` | Slasher `stakeFor(B, charlie, 0)` | `slashableStake(B, charlie, capture)` |
| ---------- | -------------------------------- | --------------------------------- | ------------------------------------- |
| `t0` right after slash `A` | `0` | `10` | n/a |
| `t1` when request `B/charlie` is created | `0` | `10` | `10` |
| `t2` three seconds later | `0` | `0` | `0` |

At `t2`:

1. `t2 - requestCreatedAt = 3s`
2. so the request is still strictly inside its own `epoch` capture window
3. but `slashableStake(...)` is already `0`

## Why This Proves The Current Logic Is Wrong

Your rule is:

1. slashing one network in a shared `subvault` must not destroy earlier slash rights for operators in other networks

But current `CompactNew` preserves those sibling slash rights only until:

1. `firstSlashTimestamp + epochDuration`

Instead of until:

1. `thisSiblingRequestTimestamp + epochDuration`

So a sibling slash request can be:

1. valid at creation time
2. still inside its own allowed capture window
3. but impossible to execute a few seconds later

That is under-slashing caused by the shared add-back expiring too early.

## Test

This witness is pinned by:

- `test_sharedSubvault_siblingRequestCanExpireBeforeItsOwnSlashWindowEnds`
