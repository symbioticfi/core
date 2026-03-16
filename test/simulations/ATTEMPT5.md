> Amounts are shown in whole tokens (1 token = 1e18).
> Epoch duration: `3 days` (`259200` seconds). Half duration: `1.5 days` (`129600` seconds). Max duration: `epoch - 1` (`259199` seconds).
> Proper = ownership-preserving stake: growth may use only truly free visible slack for that duration; it must not reduce another slot's already-visible stake at the same timestamp.
> Scenario sequence: `deposit(130)`, `createSlot(slot1,80)`, `createSlot(slot2,50)`, `wait(1d)`, `deposit(70)`, `createSlot(slot3,20)`, `setSize(slot2,70)`, `withdraw(60)`, `wait(1d)`, `setSize(slot3,30)`, `deposit(1)`, `withdraw(25)`, `snapshot`, `setSize(slot1,101)`, `snapshot`.
> Each `stakeFor` and pending cell lists values vertically in this order: `slot1`, `slot2`, `slot3`.
> `activeStake` and `activeWithdrawalsFor` are identical for both contracts in this simulation.
> Time axis below is shown as days from `cross2 t0`.

## Checkpoint values

| Checkpoint | Time from cross2 t0 | activeStake | activeWithdrawalsFor 0/half/maxDuration | stakeFor 0/half/maxDuration (Compact)                               | stakeFor 0/half/maxDuration (CompactNew)                            | stakeFor 0/half/maxDuration (Proper)                               |
| ---------- | ------------------- | ----------- | --------------------------------------- | ------------------------------------------------------------------- | ------------------------------------------------------------------- | ------------------------------------------------------------------ |
| cross2 t0  | `0d`                | 116         | 85 / 85 / 25                            | slot1: 80 / 80 / 80<br>slot2: 70 / 70 / 61<br>slot3: 30 / 30 / 0    | slot1: 80 / 80 / 80<br>slot2: 70 / 70 / 61<br>slot3: 30 / 30 / 0    | slot1: 80 / 80 / 80<br>slot2: 70 / 70 / 61<br>slot3: 30 / 30 / 0   |
| cross2 t1  | `0d`                | 116         | 85 / 85 / 25                            | slot1: 101 / 101 / 101<br>slot2: 70 / 70 / 40<br>slot3: 30 / 30 / 0 | slot1: 101 / 101 / 101<br>slot2: 70 / 70 / 40<br>slot3: 30 / 30 / 0 | slot1: 101 / 101 / 80<br>slot2: 70 / 70 / 61<br>slot3: 30 / 30 / 0 |

## What happens between checkpoints

| Interval               | Actions executed in test                                                                                                                                                                                                                                            | Net flow (deposits - withdrawals) | Delta activeStake | Delta activeWithdrawalsFor 0/half/maxDuration | Delta pending 0/half/maxDuration (Compact)               | Delta pending 0/half/maxDuration (CompactNew)            |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------- | ----------------- | --------------------------------------------- | -------------------------------------------------------- | -------------------------------------------------------- |
| 0 -> cross2 t0         | `warp(91)`, `deposit(alice,130)`, `createSlot(slot1,80)`, `createSlot(slot2,50)`, `wait(1d)`, `deposit(bob,70)`, `createSlot(slot3,20)`, `setSize(slot2,50->70)`, `withdraw(alice,60)`, `wait(1d)`, `setSize(slot3,20->30)`, `deposit(alice,1)`, `withdraw(bob,25)` | `+116`                            | `+116`            | `+85 / +85 / +25`                             | slot1: 0 / 0 / 0<br>slot2: 0 / 0 / 0<br>slot3: 0 / 0 / 0 | slot1: 0 / 0 / 0<br>slot2: 0 / 0 / 0<br>slot3: 0 / 0 / 0 |
| cross2 t0 -> cross2 t1 | `setSize(slot1,80->101)` at the same timestamp                                                                                                                                                                                                                      | `0`                               | `0`               | `0 / 0 / 0`                                   | slot1: 0 / 0 / 0<br>slot2: 0 / 0 / 0<br>slot3: 0 / 0 / 0 | slot1: 0 / 0 / 0<br>slot2: 0 / 0 / 0<br>slot3: 0 / 0 / 0 |

## Main difference

| Point                                             | Observation                                                                                                                                                                                                            |
| ------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Failure mode                                      | Growing the first slot by `+21` succeeds, but there is no `maxDuration` slack. Both contracts still let `slot1` take `21` of long-duration stake from `slot2`.                                                         |
| Broken transition                                 | `slot2` is `70 / 70 / 61` at `cross2 t0`, then becomes `70 / 70 / 40` at `cross2 t1` at the same timestamp even though `slot2` itself did nothing.                                                                     |
| Why the current growth gate is still insufficient | The gate checks only visible `d = 0` slack. That protects short durations, but it does not protect already-visible longer-duration stake when the target slot already has more `d = 0` stake than `maxDuration` stake. |
| Proper view                                       | `slot1` should gain only the short-duration slack: `101 / 101 / 80`. `slot2` should stay `70 / 70 / 61`, and `slot3` should stay `30 / 30 / 0`.                                                                        |
| Current status                                    | This bug affects both `Compact` and `CompactNew` in the same way.                                                                                                                                                      |
