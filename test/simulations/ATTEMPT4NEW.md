> Amounts are shown in whole tokens (1 token = 1e18).
> Epoch duration: `3 days` (`259200` seconds). Half duration: `1.5 days` (`129600` seconds). Max duration: `epoch - 1` (`259199` seconds).
> Proper = ownership-preserving stake: a slot keeps its own committed stake until its own size decrease becomes effective for that duration; freed stake is not reassigned to siblings automatically.
> Scenario sequence: `deposit(50)`, `createSlot(slot1,50)`, `createSlot(slot2,50)`, `withdraw(50)`, `wait(epoch-1)`, `setSize(slot1,0)`, `wait(1)`.
> Each `stakeFor` and pending cell lists values vertically in this order: `slot1`, `slot2`, `slot3`.
> `activeStake` and `activeWithdrawalsFor` are shared vault state.
> Time axis below is shown as days from `pre t0`.

## Checkpoint values

| Checkpoint | Time from pre t0 | activeStake | activeWithdrawalsFor 0/half/maxDuration | stakeFor 0/half/maxDuration (CompactNew) | stakeFor 0/half/maxDuration (Proper) |
| ---------- | ---------------- | ----------- | --------------------------------------- | ---------------------------------------- | ------------------------------------- |
| pre t0 | `0d` | 0 | 50 / 50 / 50 | slot1: 50 / 50 / 50<br>slot2: 0 / 0 / 0<br>slot3: 0 / 0 / 0 | slot1: 50 / 50 / 50<br>slot2: 0 / 0 / 0<br>slot3: 0 / 0 / 0 |
| pre t1 | `3d-1s` | 0 | 50 / 0 / 0 | slot1: 50 / 0 / 0<br>slot2: 0 / 0 / 0<br>slot3: 0 / 0 / 0 | slot1: 50 / 0 / 0<br>slot2: 0 / 0 / 0<br>slot3: 0 / 0 / 0 |
| pre t2 | `3d` | 0 | 0 / 0 / 0 | slot1: 0 / 0 / 0<br>slot2: 0 / 0 / 0<br>slot3: 0 / 0 / 0 | slot1: 0 / 0 / 0<br>slot2: 0 / 0 / 0<br>slot3: 0 / 0 / 0 |

## What happens between checkpoints

| Interval | Actions executed in test | Net flow (deposits - withdrawals) | Delta activeStake | Delta activeWithdrawalsFor 0/half/maxDuration | Delta pending 0/half/maxDuration (CompactNew) |
| -------- | ------------------------ | --------------------------------- | ----------------- | --------------------------------------------- | --------------------------------------------- |
| 0 -> pre t0 | `warp(41 days)`, `deposit(alice, 50)`, `createSlot(slot1, 50)`, `createSlot(slot2, 50)`, `withdraw(50)` | `0` | `0` | `+50 / +50 / +50` | slot1: 0 / 0 / 0<br>slot2: 0 / 0 / 0<br>slot3: 0 / 0 / 0 |
| pre t0 -> pre t1 | `wait(epoch-1)`, `setSize(slot1,0)` | `0` | `0` | `0 / -50 / -50` | slot1: +50 / +50 / +50<br>slot2: 0 / 0 / 0<br>slot3: 0 / 0 / 0 |
| pre t1 -> pre t2 | `wait(1)` | `0` | `0` | `-50 / 0 / 0` | slot1: 0 / 0 / -50<br>slot2: 0 / 0 / 0<br>slot3: 0 / 0 / 0 |

## Main difference

| Point | Observation |
| ----- | ----------- |
| Alignment | `CompactNew` matches the proper view exactly: `50 / 0 / 0` at `pre t1`, then `0 / 0 / 0` at `pre t2`. |
| Proper view | After `setSize(slot1,0)` at `3d-1s`, only `d=0` should still see the old withdrawal-backed stake; longer durations should already be zero. At `3d`, everything should be zero. |
| Result | This is another clean case where `CompactNew` does what it should. |
