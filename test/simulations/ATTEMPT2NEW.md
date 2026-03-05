> Amounts are shown in whole tokens (1 token = 1e18).
> Epoch duration: `3 days` (`259200` seconds). Half duration: `1.5 days` (`129600` seconds). Max duration: `epoch - 1` (`259199` seconds).
> Proper = ownership-preserving stake: a slot keeps its own committed stake until its own size decrease becomes effective for that duration; freed stake is not reassigned to siblings automatically.
> Each `stakeFor` and pending cell lists values vertically in this order: `slot1`, `slot2`, `slot3`.
> `activeStake` and `activeWithdrawalsFor` are shared vault state.
> Time axis below is shown as days from `div t0`.

## Checkpoint values

| Checkpoint | Time from div t0 | activeStake | activeWithdrawalsFor 0/half/maxDuration | stakeFor 0/half/maxDuration (CompactNew) | stakeFor 0/half/maxDuration (Proper) |
| ---------- | ---------------- | ----------- | --------------------------------------- | ---------------------------------------- | ------------------------------------- |
| div t0 | `0d` | 250 | 150 / 150 / 150 | slot1: 220 / 220 / 220<br>slot2: 120 / 120 / 120<br>slot3: 60 / 60 / 60 | slot1: 220 / 220 / 220<br>slot2: 120 / 120 / 120<br>slot3: 60 / 60 / 60 |
| div t1 | `2d` | 250 | 150 / 0 / 0 | slot1: 220 / 220 / 220<br>slot2: 120 / 30 / 30<br>slot3: 60 / 0 / 0 | slot1: 220 / 220 / 220<br>slot2: 120 / 30 / 30<br>slot3: 60 / 0 / 0 |
| div t2 | `4d` | 250 | 0 / 0 / 0 | slot1: 220 / 220 / 220<br>slot2: 30 / 20 / 20<br>slot3: 0 / 0 / 0 | slot1: 220 / 220 / 220<br>slot2: 30 / 20 / 20<br>slot3: 0 / 0 / 0 |
| div t3 | `5d-1s` | 250 | 0 / 0 / 0 | slot1: 220 / 220 / 220<br>slot2: 30 / 20 / 20<br>slot3: 0 / 0 / 0 | slot1: 220 / 220 / 220<br>slot2: 30 / 20 / 20<br>slot3: 0 / 0 / 0 |
| div t4 | `5d` | 250 | 0 / 0 / 0 | slot1: 220 / 220 / 220<br>slot2: 20 / 20 / 20<br>slot3: 10 / 10 / 10 | slot1: 220 / 220 / 220<br>slot2: 20 / 20 / 20<br>slot3: 10 / 10 / 10 |

## What happens between checkpoints

| Interval | Actions executed in test | Net flow (deposits - withdrawals) | Delta activeStake | Delta activeWithdrawalsFor 0/half/maxDuration | Delta pending 0/half/maxDuration (CompactNew) |
| -------- | ------------------------ | --------------------------------- | ----------------- | --------------------------------------------- | --------------------------------------------- |
| 0 -> div t0 | `warp(21)`, `deposit(alice, 400)`, `createSlot(slot1, 220)`, `createSlot(slot2, 120)`, `createSlot(slot3, 60)`, `withdraw(alice, 150)` | `+250` | `+250` | `+150 / +150 / +150` | slot1: 0 / 0 / 0<br>slot2: 0 / 0 / 0<br>slot3: 0 / 0 / 0 |
| div t0 -> div t1 | `setSize(slot2, 120->20)`, `setSize(slot3, 60->10)` | `0` | `0` | `0 / -150 / -150` | slot1: 0 / 0 / 0<br>slot2: +100 / +100 / +100<br>slot3: +50 / +50 / +50 |
| div t1 -> div t2 | `warp` only (pending and withdrawal windows move) | `0` | `0` | `-150 / 0 / 0` | slot1: 0 / 0 / 0<br>slot2: 0 / -100 / -100<br>slot3: 0 / -50 / -50 |
| div t2 -> div t3 | `warp` only | `0` | `0` | `0 / 0 / 0` | slot1: 0 / 0 / 0<br>slot2: 0 / 0 / 0<br>slot3: 0 / 0 / 0 |
| div t3 -> div t4 | `warp(1)` only | `0` | `0` | `0 / 0 / 0` | slot1: 0 / 0 / 0<br>slot2: -100 / 0 / 0<br>slot3: -50 / 0 / 0 |

## Main difference

| Point | Observation |
| ----- | ----------- |
| Before `5d` | `CompactNew` now stays aligned with the proper priority-preserving view instead of reviving `slot3` on longer durations. |
| Proper view | The tail shrinks cleanly: `slot2` keeps `30 / 20 / 20` at `div t2/div t3`, while `slot3` stays `0 / 0 / 0` until `5d`. |
| At `5d` | Once the last `d=0` pending clears, `CompactNew` remains aligned with the proper distribution: `220 / 20 / 10`. |
