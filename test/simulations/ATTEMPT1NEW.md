> Amounts are shown in whole tokens (1 token = 1e18).
> Epoch duration: `3 days` (`259200` seconds). Half duration: `1.5 days` (`129600` seconds). Max duration: `epoch - 1` (`259199` seconds).
> Proper = ownership-preserving stake: a slot keeps its own committed stake until its own size decrease becomes effective for that duration; freed stake is not reassigned to siblings automatically.
> Each `stakeFor` and pending cell lists values vertically in this order: `slot1`, `slot2`, `slot3`.
> `activeStake` and `activeWithdrawalsFor` are shared vault state.
> Time axis below is shown as days from `t0`.

## Checkpoint values

| Checkpoint | Time from t0 | activeStake | activeWithdrawalsFor 0/half/maxDuration | stakeFor 0/half/maxDuration (CompactNew)                                   | stakeFor 0/half/maxDuration (Proper)                                       |
| ---------- | ------------ | ----------- | --------------------------------------- | -------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| t0         | `0d`         | 1000        | 0 / 0 / 0                               | slot1: 400 / 400 / 400<br>slot2: 0 / 0 / 0<br>slot3: 0 / 0 / 0             | slot1: 400 / 400 / 400<br>slot2: 0 / 0 / 0<br>slot3: 0 / 0 / 0             |
| t1         | `1d`         | 1070        | 180 / 180 / 180                         | slot1: 520 / 520 / 520<br>slot2: 250 / 250 / 250<br>slot3: 0 / 0 / 0       | slot1: 520 / 520 / 520<br>slot2: 250 / 250 / 250<br>slot3: 0 / 0 / 0       |
| t2         | `2d`         | 1050        | 290 / 290 / 110                         | slot1: 520 / 520 / 520<br>slot2: 320 / 320 / 320<br>slot3: 120 / 120 / 120 | slot1: 520 / 520 / 520<br>slot2: 320 / 320 / 320<br>slot3: 120 / 120 / 120 |
| t3         | `4d`         | 1030        | 200 / 90 / 90                           | slot1: 520 / 520 / 520<br>slot2: 320 / 320 / 320<br>slot3: 160 / 160 / 160 | slot1: 520 / 520 / 460<br>slot2: 320 / 320 / 320<br>slot3: 160 / 160 / 160 |
| t4         | `7d`         | 1010        | 60 / 60 / 60                            | slot1: 460 / 460 / 460<br>slot2: 320 / 320 / 320<br>slot3: 160 / 160 / 160 | slot1: 460 / 460 / 460<br>slot2: 320 / 320 / 260<br>slot3: 160 / 160 / 100 |

## What happens between checkpoints

| Interval | Actions executed in test                                                                          | Net flow (deposits - withdrawals) | Delta activeStake | Delta activeWithdrawalsFor 0/half/maxDuration | Delta pending 0/half/maxDuration (CompactNew)                              |
| -------- | ------------------------------------------------------------------------------------------------- | --------------------------------- | ----------------- | --------------------------------------------- | -------------------------------------------------------------------------- |
| 0 -> t0  | `warp(1)`, `deposit(alice, 1000)`, `createSlot(slot1, 400)`                                       | `+1000`                           | `+1000`           | `0 / 0 / 0`                                   | slot1: 0 / 0 / 0<br>slot2: 0 / 0 / 0<br>slot3: 0 / 0 / 0                   |
| t0 -> t1 | `deposit(bob, 250)`, `createSlot(250)`, `setSize(slot1, 400->520)`, `withdraw(alice, 180)`        | `+70`                             | `+70`             | `+180 / +180 / +180`                          | slot1: 0 / 0 / 0<br>slot2: 0 / 0 / 0<br>slot3: 0 / 0 / 0                   |
| t1 -> t2 | `createSlot(120)`, `setSize(slot2, 250->320)`, `deposit(alice, 90)`, `withdraw(bob, 110)`         | `-20`                             | `-20`             | `+110 / +110 / -70`                           | slot1: 0 / 0 / 0<br>slot2: 0 / 0 / 0<br>slot3: 0 / 0 / 0                   |
| t2 -> t3 | `setSize(slot1, 520->460)`, `setSize(slot3, 120->160)`, `deposit(bob, 70)`, `withdraw(alice, 90)` | `-20`                             | `-20`             | `-90 / -200 / -20`                            | slot1: +60 / +60 / +60<br>slot2: 0 / 0 / 0<br>slot3: 0 / 0 / 0             |
| t3 -> t4 | `setSize(slot2, 320->260)`, `setSize(slot3, 160->100)`, `deposit(alice, 40)`, `withdraw(bob, 60)` | `-20`                             | `-20`             | `-140 / -30 / -30`                            | slot1: -60 / -60 / -60<br>slot2: +60 / +60 / +60<br>slot3: +60 / +60 / +60 |

## Main difference

| Point              | Observation                                                                                                           |
| ------------------ | --------------------------------------------------------------------------------------------------------------------- |
| Current CompactNew | `CompactNew` stays aligned with the old max-duration sizes through `t3` and `t4`.                                     |
| Proper view        | Long-duration stake should reflect each slot's own size decreases: `slot1` at `t3`, then `slot2` and `slot3` at `t4`. |
| Net result         | This scenario is mostly stable; the only mismatch is delayed long-duration shrinkage in `CompactNew`.                 |
