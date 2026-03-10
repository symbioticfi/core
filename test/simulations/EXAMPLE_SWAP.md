> Amounts are shown in whole tokens (1 token = 1e18).
> Epoch duration in the CompactNew simulation is `3 days`.
> This file documents the current conclusion for `UniversalDelegatorCompactNew.swapSlots`.

## Current conclusion

I do not have a truthful `CompactNew` example that proves the current `swapSlots` logic is wrong.

The old swap witness was for production `UniversalDelegator`, not for `CompactNew`.

## Why the old witness does not transpose

The old production witness relied on a mixed state like:

- `slot1 = 50 / 50 / 0`
- `slot2 = 0 / 0 / 50`

Current `CompactNew` does not produce that state in the matching pending-window scenario.

The closest CompactNew state is:

| Slot | `stakeFor(0)` | `stakeFor(half)` | `stakeFor(maxDuration)` |
| ---- | ------------- | ---------------- | ----------------------- |
| `slot1` | `50` | `0` | `0` |
| `slot2` | `0` | `0` | `0` |

and `swapSlots(slot1, slot2)` reverts there.

## Why the current guard may actually be sound

Current CompactNew guard:

1. Branch A allows the swap only if the full `d = 0` prefix through `index2` still fits into `balance(maxDuration)`.
2. Branch B allows the swap only if the prefix before `index1` at `maxDuration` already exhausts `balance(0)`.

Practical meaning:

1. Branch A means the whole swap window is already fully allocated even under the strongest prefix accounting, so reordering does not create a mixed-duration ownership transfer.
2. Branch B means the prefix before `index1` already consumes all visible balance, so `index1` and later slots are zero anyway.

## Search performed

I also ran sampled searches against current CompactNew:

- adjacent and non-adjacent pairs
- 3-slot and 4-slot states
- withdrawals, deposits, downsizes, waits
- only monotone pre-swap states considered

No allowed CompactNew swap witness was found where the swap changed visible stake in a way that looked invalid.

## Result

For current `CompactNew`, I cannot honestly provide `EXAMPLE_SWAP` as a proof of wrongness.

If you still want to challenge this logic, the next useful step is a stronger exhaustive search over:

1. all 3-slot states with bounded sizes
2. all pending-expiry boundary timestamps
3. all allowed swap pairs
