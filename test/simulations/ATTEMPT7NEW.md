> Amounts are shown in whole tokens (1 token = 1e18).
> Epoch duration: `3 days`. Half duration: `1.5 days`. Max duration: `epoch - 1`.
> Proper = duration-aware priority allocation. A previous sibling blocks later slots only with `size + pending(duration)`, not `size + pending(0)`.
> This is a shrink-only deterministic witness.

## Scenario

`warp(1035) -> deposit(244) -> createSlot(slot1,78) -> createSlot(slot2,40) -> createSlot(slot3,85) -> createSlot(slot4,137) -> withdraw(73) -> withdraw(32) -> setSize(slot2,40->4) -> deposit(32) -> wait(1.5d)`

## Key checkpoints

| Checkpoint                                                 | activeStake | activeWithdrawalsFor 0/half/max | slot2 pending 0/half/max | slot3 stakeFor 0/half/max (CompactNew) | slot3 stakeFor 0/half/max (Proper) |
| ---------------------------------------------------------- | ----------- | ------------------------------- | ------------------------ | -------------------------------------- | ---------------------------------- |
| `t0` after initial setup                                   | 244         | `0 / 0 / 0`                     | `0 / 0 / 0`              | `85 / 85 / 85`                         | `85 / 85 / 85`                     |
| `t1` after `withdraw, withdraw, setSize(slot2,4), deposit` | 171         | `105 / 105 / 105`               | `36 / 36 / 36`           | `85 / 85 / 85`                         | `85 / 85 / 85`                     |
| `t2 = t1 + 1.5d`                                           | 171         | `105 / 0 / 0`                   | `36 / 0 / 0`             | `85 / 53 / 53`                         | `85 / 85 / 85`                     |

## Why it is wrong

At `t2`, the `36` pending on `slot2` is still alive only for `d = 0`.

So for `slot3`:

- current code uses previous-sibling sum `78 + 4 + 36 = 118` for `half/max`
- proper logic should use `78 + 4 + 0 = 82` for `half/max`

That gives:

- current `stakeFor(slot3, half) = min(171 - 118, 85) = 53`
- proper `stakeFor(slot3, half) = min(171 - 82, 85) = 85`

Same for `max`.

## Root cause

`setSize(slot2,40->4)` correctly creates `36` pending at `d = 0`, but later reads still subtract that `pending(0)` from later siblings at `half/max`.

So a pure time shift makes `slot3` lose `32` stake that should already be free again.
