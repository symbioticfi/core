> Amounts are shown in whole tokens (1 token = 1e18).
> Epoch duration: `3 days` (`259200` seconds). Half duration: `1.5 days` (`129600` seconds). Max duration: `epoch - 1` (`259199` seconds).
> Proper = ownership-preserving stake: a slot keeps its own committed stake until its own size decrease becomes effective for that duration; freed stake is not reassigned to siblings automatically.
> Scenario sequence: `setSizes(100)`, `deposit(100)`, `withdraw(100)`, `wait(epoch-1)`, `setSize(slot1,0)`, `wait(1)`.
> Each `stakeFor` and pending cell lists values vertically in this order: `slot1`, `slot2`, `slot3`.
> `activeStake` and `activeWithdrawalsFor` are identical for both contracts in this simulation.
> Time axis below is shown as days from `zero t0`.

## Checkpoint values

| Checkpoint | Time from zero t0 | activeStake | activeWithdrawalsFor 0/half/maxDuration | stakeFor 0/half/maxDuration (Compact) | stakeFor 0/half/maxDuration (CompactNew) | stakeFor 0/half/maxDuration (Proper) |
| ---------- | ----------------- | ----------- | --------------------------------------- | ------------------------------------- | ---------------------------------------- | ------------------------------------- |
| zero t0 | `0d` | 100 | 0 / 0 / 0 | slot1: 100 / 100 / 100<br>slot2: 0 / 0 / 0<br>slot3: 0 / 0 / 0 | slot1: 100 / 100 / 100<br>slot2: 0 / 0 / 0<br>slot3: 0 / 0 / 0 | slot1: 100 / 100 / 100<br>slot2: 0 / 0 / 0<br>slot3: 0 / 0 / 0 |
| zero t1 | `0d` | 0 | 100 / 100 / 100 | slot1: 100 / 100 / 100<br>slot2: 0 / 0 / 0<br>slot3: 0 / 0 / 0 | slot1: 100 / 100 / 100<br>slot2: 0 / 0 / 0<br>slot3: 0 / 0 / 0 | slot1: 100 / 100 / 100<br>slot2: 0 / 0 / 0<br>slot3: 0 / 0 / 0 |
| zero t2 | `3d-1s` | 0 | 100 / 0 / 0 | slot1: 100 / 100 / 100<br>slot2: 0 / 0 / 0<br>slot3: 0 / 0 / 0 | slot1: 100 / 0 / 0<br>slot2: 0 / 0 / 0<br>slot3: 0 / 0 / 0 | slot1: 100 / 0 / 0<br>slot2: 0 / 0 / 0<br>slot3: 0 / 0 / 0 |
| zero t3 | `3d` | 0 | 0 / 0 / 0 | slot1: 100 / 100 / 0<br>slot2: 0 / 0 / 0<br>slot3: 0 / 0 / 0 | slot1: 0 / 0 / 0<br>slot2: 0 / 0 / 0<br>slot3: 0 / 0 / 0 | slot1: 0 / 0 / 0<br>slot2: 0 / 0 / 0<br>slot3: 0 / 0 / 0 |

## What happens between checkpoints

| Interval | Actions executed in test | Net flow (deposits - withdrawals) | Delta activeStake | Delta activeWithdrawalsFor 0/half/maxDuration | Delta pending 0/half/maxDuration (Compact) | Delta pending 0/half/maxDuration (CompactNew) |
| -------- | ------------------------ | --------------------------------- | ----------------- | --------------------------------------------- | ------------------------------------------ | --------------------------------------------- |
| 0 -> zero t0 | `warp(31)`, `createSlot(slot1,0)`, `createSlot(slot2,0)`, `createSlot(slot3,0)`, `setSize(slot1,100)`, `setSize(slot2,100)`, `setSize(slot3,100)`, `deposit(100)` | `+100` | `+100` | `0 / 0 / 0` | slot1: 0 / 0 / 0<br>slot2: 0 / 0 / 0<br>slot3: 0 / 0 / 0 | slot1: 0 / 0 / 0<br>slot2: 0 / 0 / 0<br>slot3: 0 / 0 / 0 |
| zero t0 -> zero t1 | `withdraw(100)` | `-100` | `-100` | `+100 / +100 / +100` | slot1: 0 / 0 / 0<br>slot2: 0 / 0 / 0<br>slot3: 0 / 0 / 0 | slot1: 0 / 0 / 0<br>slot2: 0 / 0 / 0<br>slot3: 0 / 0 / 0 |
| zero t1 -> zero t2 | `wait(epoch-1)`, `setSize(slot1,0)` | `0` | `0` | `0 / -100 / -100` | slot1: +100 / +100 / +100<br>slot2: 0 / 0 / 0<br>slot3: 0 / 0 / 0 | slot1: +100 / +100 / +100<br>slot2: 0 / 0 / 0<br>slot3: 0 / 0 / 0 |
| zero t2 -> zero t3 | `wait(1)` | `0` | `0` | `-100 / 0 / 0` | slot1: 0 / 0 / -100<br>slot2: 0 / 0 / 0<br>slot3: 0 / 0 / 0 | slot1: 0 / 0 / -100<br>slot2: 0 / 0 / 0<br>slot3: 0 / 0 / 0 |

## Main difference

| Point | Observation |
| ----- | ----------- |
| Proper view | Once `slot1` is set to zero near the boundary, only `d=0` should still carry the old withdrawal-backed stake; longer durations should already be zero. |
| Alignment | `CompactNew` matches the proper view here at `zero t2` and `zero t3`. |
| Compact issue | `Compact` keeps `slot1` over-allocated for longer durations after its own size has already dropped to zero. |
