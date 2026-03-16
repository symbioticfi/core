> Amounts are shown in whole tokens (1 token = 1e18).
> Epoch duration: `3 days` (`259200` seconds). Half duration: `1.5 days` (`129600` seconds). Max duration: `epoch - 1` (`259199` seconds).
> Proper = ownership-preserving stake: a slot keeps its own committed stake until its own size decrease becomes effective for that duration; freed stake is not reassigned to siblings automatically.
> Each `stakeFor` and pending cell lists values vertically in this order: `slot1`, `slot2`, `slot3`.
> `activeStake` and `activeWithdrawalsFor` are identical for both contracts in this simulation.
> Time axis below is shown as days from `div t0`.

## Checkpoint values

| Checkpoint | Time from div t0 | activeStake | activeWithdrawalsFor 0/half/maxDuration | stakeFor 0/half/maxDuration (Compact)                             | stakeFor 0/half/maxDuration (CompactNew)                          | stakeFor 0/half/maxDuration (Proper)                              |
| ---------- | ---------------- | ----------- | --------------------------------------- | ----------------------------------------------------------------- | ----------------------------------------------------------------- | ----------------------------------------------------------------- |
| div t0     | `0d`             | 250         | 150 / 150 / 150                         | slot1: 220 / 220 / 220 slot2: 120 / 120 / 120 slot3: 60 / 60 / 60 | slot1: 220 / 220 / 220 slot2: 120 / 120 / 120 slot3: 60 / 60 / 60 | slot1: 220 / 220 / 220 slot2: 120 / 120 / 120 slot3: 60 / 60 / 60 |
| div t1     | `2d`             | 250         | 150 / 0 / 0                             | slot1: 220 / 100 / 100 slot2: 120 / 100 / 100 slot3: 60 / 50 / 50 | slot1: 220 / 220 / 220 slot2: 120 / 30 / 30 slot3: 60 / 0 / 0     | slot1: 220 / 220 / 220 slot2: 120 / 30 / 30 slot3: 60 / 0 / 0     |
| div t2     | `4d`             | 250         | 0 / 0 / 0                               | slot1: 100 / 220 / 220 slot2: 100 / 20 / 20 slot3: 50 / 10 / 10   | slot1: 220 / 220 / 220 slot2: 30 / 20 / 20 slot3: 0 / 0 / 0       | slot1: 220 / 220 / 220 slot2: 30 / 20 / 20 slot3: 0 / 0 / 0       |
| div t3     | `5d-1s`          | 250         | 0 / 0 / 0                               | slot1: 100 / 220 / 220 slot2: 100 / 20 / 20 slot3: 50 / 10 / 10   | slot1: 220 / 220 / 220 slot2: 30 / 20 / 20 slot3: 0 / 0 / 0       | slot1: 220 / 220 / 220 slot2: 30 / 20 / 20 slot3: 0 / 0 / 0       |
| div t4     | `5d`             | 250         | 0 / 0 / 0                               | slot1: 220 / 220 / 220 slot2: 20 / 20 / 20 slot3: 10 / 10 / 10    | slot1: 220 / 220 / 220 slot2: 20 / 20 / 20 slot3: 10 / 10 / 10    | slot1: 220 / 220 / 220 slot2: 20 / 20 / 20 slot3: 10 / 10 / 10    |

## What happens between checkpoints

| Interval         | Actions executed in test                                                                                                               | Net flow (deposits - withdrawals) | Delta activeStake | Delta activeWithdrawalsFor 0/half/maxDuration | Delta pending 0/half/maxDuration (Compact)                        | Delta pending 0/half/maxDuration (CompactNew)                     |
| ---------------- | -------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------- | ----------------- | --------------------------------------------- | ----------------------------------------------------------------- | ----------------------------------------------------------------- |
| 0 -> div t0      | `warp(21)`, `deposit(alice, 400)`, `createSlot(slot1, 220)`, `createSlot(slot2, 120)`, `createSlot(slot3, 60)`, `withdraw(alice, 150)` | `+250`                            | `+250`            | `+150 / +150 / +150`                          | slot1: 0 / 0 / 0 slot2: 0 / 0 / 0 slot3: 0 / 0 / 0                | slot1: 0 / 0 / 0 slot2: 0 / 0 / 0 slot3: 0 / 0 / 0                |
| div t0 -> div t1 | `setSize(slot2, 120->20)`, `setSize(slot3, 60->10)`                                                                                    | `0`                               | `0`               | `0 / -150 / -150`                             | slot1: 0 / 0 / 0 slot2: +100 / +100 / +100 slot3: +50 / +50 / +50 | slot1: 0 / 0 / 0 slot2: +100 / +100 / +100 slot3: +50 / +50 / +50 |
| div t1 -> div t2 | `warp` only (pending and withdrawal windows move)                                                                                      | `0`                               | `0`               | `-150 / 0 / 0`                                | slot1: 0 / 0 / 0 slot2: 0 / -100 / -100 slot3: 0 / -50 / -50      | slot1: 0 / 0 / 0 slot2: 0 / -100 / -100 slot3: 0 / -50 / -50      |
| div t2 -> div t3 | `warp` only                                                                                                                            | `0`                               | `0`               | `0 / 0 / 0`                                   | slot1: 0 / 0 / 0 slot2: 0 / 0 / 0 slot3: 0 / 0 / 0                | slot1: 0 / 0 / 0 slot2: 0 / 0 / 0 slot3: 0 / 0 / 0                |
| div t3 -> div t4 | `warp(1)` only                                                                                                                         | `0`                               | `0`               | `0 / 0 / 0`                                   | slot1: 0 / 0 / 0 slot2: -100 / 0 / 0 slot3: -50 / 0 / 0           | slot1: 0 / 0 / 0 slot2: -100 / 0 / 0 slot3: -50 / 0 / 0           |

## Main difference

| Point             | Observation                                                                                                                                                                    |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Proper view       | `slot1` should stay at `220` throughout; `slot2` and `slot3` should only shrink to their own new sizes, not donate stake to `slot1`.                                           |
| Compact issue     | `Compact` still overfills earlier slots before `5d`, first collapsing `slot1` at `d=0`, then reviving it on longer durations and giving `slot3` long-duration stake too early. |
| CompactNew result | With the `min(duration, 0)` clamp, `CompactNew` now matches the proper distribution at every checkpoint in this scenario.                                                      |
