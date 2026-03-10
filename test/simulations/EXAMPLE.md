> Amounts are shown in whole tokens (1 token = 1e18).
> Epoch duration: `3 days`. Half duration: `1.5 days`. Max duration: `epoch - 1`.
> This is the current live example for: `setSize + time + getAllocated`, not `setSize` alone.

## Scenario

`deposit(244)`, `createSlot(slot1,78)`, `createSlot(slot2,40)`, `createSlot(slot3,85)`, `createSlot(slot4,137)`, `withdraw(73)`, `withdraw(32)`, `setSize(slot2,40->4)`, `deposit(32)`, `wait(1.5d)`

## Checkpoints

| Checkpoint | Meaning |
| ---------- | ------- |
| `t0` | initial state |
| `t1` | immediately after `withdraw, withdraw, setSize(slot2,40->4), deposit` |
| `t2` | after `wait(1.5d)` |

## State table

| Checkpoint | activeStake | activeWithdrawalsFor 0/half/maxDuration | slot2 pending 0/half/maxDuration | current slot2 `stakeFor` | current slot3 `stakeFor` | current slot4 `stakeFor` | proper slot2 `stakeFor` | proper slot3 `stakeFor` | proper slot4 `stakeFor` |
| ---------- | ----------- | --------------------------------------- | -------------------------------- | ------------------------ | ------------------------ | ------------------------ | ----------------------- | ----------------------- | ----------------------- |
| `t0` | `244` | `0 / 0 / 0` | `0 / 0 / 0` | `40 / 40 / 40` | `85 / 85 / 85` | `41 / 41 / 41` | `40 / 40 / 40` | `85 / 85 / 85` | `41 / 41 / 41` |
| `t1` | `171` | `105 / 105 / 105` | `36 / 36 / 36` | `40 / 40 / 40` | `85 / 85 / 85` | `73 / 73 / 73` | `40 / 40 / 40` | `85 / 85 / 85` | `73 / 73 / 73` |
| `t2` | `171` | `105 / 0 / 0` | `36 / 0 / 0` | `40 / 4 / 4` | `85 / 53 / 53` | `73 / 0 / 0` | `40 / 4 / 4` | `85 / 85 / 85` | `73 / 4 / 4` |

## What this shows

At `t1`, right after `setSize(slot2,40->4)`:

1. current and proper still match
2. `slot2` correctly carries `36` pending
3. there is no visible contradiction yet

At `t2`, after only a time shift:

1. `slot2.pending(half)` and `slot2.pending(maxDuration)` are already `0`
2. but `slot3` is still reduced from `85` to `53`
3. and `slot4` is still reduced from `73 / 4 / 4` to `73 / 0 / 0`

So the divergence appears only after:

1. `setSize` wrote the state
2. time moved
3. `getAllocated(half/maxDuration)` read that state

## Why this is not a direct `setSize` proof

If `setSize` itself were the direct bug, the mismatch would already be visible at `t1`.

It is not.

The mismatch starts only at `t2`, when later reads still block downstream slots too much after the shorter pending has already expired for `half/maxDuration`.

So this example proves:

- the live problem is in the state evolution as read by `getAllocated`
- not in the immediate write effect of `setSize` alone

## Source

- `test_seed35_referenceDivergenceTimeline`
