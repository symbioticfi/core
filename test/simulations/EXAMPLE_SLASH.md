> Amounts are shown in whole tokens (1 token = 1e18).
> Epoch duration: `3 days`. Half duration: `1.5 days`. Max duration: `epoch - 1`.
> This example matches the current slash invariant semantics for `CompactNew`.

## Slash invariant

After one slot is slashed:

1. Any sibling's `stakeFor` may decrease.
2. The slashed slot's own `stakeFor(d)` must not decrease by more than the slashed amount.

## Effective scenario

This is the deterministic replay witness from `seed = 3`:

1. `deposit(193)`
2. `createSlot(slot1,86)`
3. `createSlot(slot2,44)`
4. `createSlot(slot3,69)`
5. `createSlot(slot4,102)`
6. `deposit(70)`
7. `setSize(slot3,69->34.5)` creating pending `34.5 / 34.5 / 34.5`
8. `wait(1s)`
9. `slash(slot1, 15)`

## Checkpoints

| Checkpoint        | Timestamp | activeStake | activeWithdrawalsFor 0/half/maxDuration | slot1 `stakeFor` | slot2 `stakeFor` | slot3 `stakeFor` | slot4 `stakeFor` |
| ----------------- | --------- | ----------- | --------------------------------------- | ---------------- | ---------------- | ---------------- | ---------------- |
| `t1` before slash | `1004`    | `263`       | `0 / 0 / 0`                             | `86 / 86 / 86`   | `44 / 44 / 44`   | `69 / 69 / 34.5` | `64 / 64 / 64`   |
| `t2` after slash  | `1004`    | `248`       | `0 / 0 / 0`                             | `71 / 71 / 71`   | `44 / 44 / 44`   | `69 / 69 / 34.5` | `64 / 64 / 64`   |

## Slashed slot bound

The slashed slot is `slot1`.

- slash amount: `15`
- `stakeFor(0)`: `86 -> 71`, drop = `15`
- `stakeFor(half)`: `86 -> 71`, drop = `15`
- `stakeFor(maxDuration)`: `86 -> 71`, drop = `15`

So the slashed slot does not lose more than the slashed amount at any sampled duration.

## Notes

- A sibling drop after slash would be allowed by this invariant.
- This example is a pass-case for the current slash bound, not a violation.

## Source

- Permanent test: `test_seed3_slashOnlyReducesOwnStakeBySlashedAmount`
- Sampled search: `test_searchSlashDoesNotReduceOwnStakeByMoreThanAmount`
