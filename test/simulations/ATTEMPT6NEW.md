> Amounts are shown in whole tokens (1 token = 1e18).
> Epoch duration: `3 days` (`259200` seconds). Half duration: `1.5 days` (`129600` seconds). Max duration: `epoch - 1` (`259199` seconds).
> Proper = sampled reference model: for each duration, allocate sequentially by `size + pending(duration)`, then clamp per slot so `stakeFor(0) >= stakeFor(half) >= stakeFor(maxDuration)`.
> Each `stakeFor` and pending cell lists values vertically in this order: `slot1`, `slot2`, `slot3`, `slot4`.
> `activeStake` and `activeWithdrawalsFor` are shared vault state.
> Scenario sequence: `warp(1035)`, `deposit(alice,244)`, `createSlot(slot1,78)`, `createSlot(slot2,40)`, `createSlot(slot3,85)`, `createSlot(slot4,137)`, `withdraw(alice,73)`, `withdraw(alice,32)`, `setSize(slot2,40->4)`, `deposit(alice,32)`, `wait(1.5d)`.
> Time axis below is shown from `seed35 t0`.

## Checkpoint values

| Checkpoint | Time from seed35 t0 | activeStake | activeWithdrawalsFor 0/half/maxDuration | stakeFor 0/half/maxDuration (CompactNew)                                        | stakeFor 0/half/maxDuration (Proper)                                            |
| ---------- | ------------------- | ----------- | --------------------------------------- | ------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| seed35 t0  | `0d`                | 244         | 0 / 0 / 0                               | slot1: 78 / 78 / 78 slot2: 40 / 40 / 40 slot3: 85 / 85 / 85 slot4: 41 / 41 / 41 | slot1: 78 / 78 / 78 slot2: 40 / 40 / 40 slot3: 85 / 85 / 85 slot4: 41 / 41 / 41 |
| seed35 t1  | `0d`                | 171         | 105 / 105 / 105                         | slot1: 78 / 78 / 78 slot2: 40 / 40 / 40 slot3: 85 / 85 / 85 slot4: 73 / 73 / 73 | slot1: 78 / 78 / 78 slot2: 40 / 40 / 40 slot3: 85 / 85 / 85 slot4: 73 / 73 / 73 |
| seed35 t2  | `1.5d`              | 171         | 105 / 0 / 0                             | slot1: 78 / 78 / 78 slot2: 40 / 4 / 4 slot3: 85 / 53 / 53 slot4: 73 / 0 / 0     | slot1: 78 / 78 / 78 slot2: 40 / 4 / 4 slot3: 85 / 85 / 85 slot4: 73 / 4 / 4     |

## What happens between checkpoints

| Interval               | Actions executed in test                                                                                              | Net flow (deposits - withdrawals) | Delta activeStake | Delta activeWithdrawalsFor 0/half/maxDuration | Delta pending 0/half/maxDuration (CompactNew)                             |
| ---------------------- | --------------------------------------------------------------------------------------------------------------------- | --------------------------------- | ----------------- | --------------------------------------------- | ------------------------------------------------------------------------- |
| 0 -> seed35 t0         | `deposit(alice,244)`, `createSlot(slot1,78)`, `createSlot(slot2,40)`, `createSlot(slot3,85)`, `createSlot(slot4,137)` | `+244`                            | `+244`            | `0 / 0 / 0`                                   | slot1: 0 / 0 / 0 slot2: 0 / 0 / 0 slot3: 0 / 0 / 0 slot4: 0 / 0 / 0       |
| seed35 t0 -> seed35 t1 | `withdraw(alice,73)`, `withdraw(alice,32)`, `setSize(slot2,40->4)`, `deposit(alice,32)`                               | `-73`                             | `-73`             | `+105 / +105 / +105`                          | slot1: 0 / 0 / 0 slot2: +36 / +36 / +36 slot3: 0 / 0 / 0 slot4: 0 / 0 / 0 |
| seed35 t1 -> seed35 t2 | `warp(1.5d)` only                                                                                                     | `0`                               | `0`               | `0 / -105 / -105`                             | slot1: 0 / 0 / 0 slot2: 0 / -36 / -36 slot3: 0 / 0 / 0 slot4: 0 / 0 / 0   |

## Main difference

| Point               | Observation                                                                                                                                                                                                                                                    |
| ------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Failure mode        | `slot2` was downsized at `t1`, creating `36` pending. After `1.5d`, that pending should matter only for `d = 0`. `CompactNew` still subtracts it from later siblings for `half/max` because previous-sibling pending is read with `d = 0` inside `getPrevSum`. |
| Broken transition   | `slot3` is `85 / 85 / 85` at `seed35 t1`, then becomes `85 / 53 / 53` at `seed35 t2` after a pure time shift. `slot4` also drops from `73 / 73 / 73` to `73 / 0 / 0`.                                                                                          |
| Proper view         | Once the half-duration window has passed, `slot2` should be only `4 / 4 / 4` on its own size. `slot3` should stay `85 / 85 / 85`, and `slot4` should still keep the remaining `73 / 4 / 4`.                                                                    |
| Why seed 35 matters | This is a deterministic replay of the witness found by the proof search: `seed = 35`, `step = 4`, `label = warp`, `timestamp = 130635`. The divergence comes from time progression alone, not from a new state-changing action at the divergence point.        |
