> Amounts are shown in whole tokens (1 token = 1e18).
> Epoch duration: `3 days`.
> This is a larger illustrative example for the current production `UniversalDelegator` shared-subvault semantics.
> It focuses on `stakeFor(..., 0)` and `slashableStake(..., 0)` only.

## Core Idea

For shared subvaults under the current production model:

1. Public `stakeFor()` is the real-time funded view.
2. `slashableStake()` can preserve sibling-network guarantees inside a shared subvault.
3. A fresh network does not inherit older shared slash credit.
4. Pending-based sibling preservation lasts only until the original pending expires.
5. Root ordering still matters: subvaults before a shared one can starve it, and a shared subvault before another one can starve the later shared subtree completely.

## Root Order

The root has four children in this exact order:

1. `isolatedSubvaultX(6)`
2. `sharedSubvaultA(10)`
3. `isolatedSubvaultY(4)`
4. `sharedSubvaultB(8)`

That order is what drives the root-funded curve.

## Local Layout

### `isolatedSubvaultX`

- `networkX(6)`
- `xavier(6)`

### `sharedSubvaultA`

- `networkA1(10)`
  - `alice(6)`
  - `bob(4)`
- `networkA2(7)`
  - `carol(3)`
  - `dave(4)`
- later: `networkA3(10)`
  - `iris(5)`
  - `jack(5)`

### `isolatedSubvaultY`

- `networkY(4)`
- `yves(4)`

### `sharedSubvaultB`

- `networkB1(8)`
  - `erin(5)`
  - `frank(3)`
- `networkB2(5)`
  - `gina(2)`
  - `hank(3)`

## Scenario Sequence

1. Create all root subvaults in the order above.
2. Create all listed networks and operators except `networkA3`.
3. `deposit(20)`
4. Slash `networkA1/alice` by `3`
5. `withdraw(5)`
6. Create fresh `networkA3(10)` with `iris(5)` and `jack(5)`
7. `setSize(sharedSubvaultA, 4)`
8. `wait(epoch + 1s)` so that the shared pending created by step 7 expires
9. `deposit(8)`

## Root-Funded Subvault Curve

| Checkpoint | `activeStake` | `isolatedX` funded | `sharedA` funded | `isolatedY` funded | `sharedB` funded |
| --- | ---: | ---: | ---: | ---: | ---: |
| `t0` after `deposit(20)` | `20` | `6` | `10` | `4` | `0` |
| `t1` after slash `A/alice = 3` | `17` | `6` | `7` | `4` | `0` |
| `t2` after `withdraw(5)` | `12` | `6` | `7` | `4` | `0` |
| `t3` after fresh `networkA3` | `12` | `6` | `7` | `4` | `0` |
| `t4` after `setSize(sharedA, 4)` | `12` | `6` | `7` | `4` | `0` |
| `t5` after pending expiry | `12` | `6` | `4` | `2` | `0` |
| `t6` after `deposit(8)` | `20` | `6` | `4` | `4` | `6` |

## Public `stakeFor(..., 0)`

| Checkpoint | `alice` | `bob` | `carol` | `dave` | `iris` | `jack` | `xavier` | `yves` | `erin` | `frank` | `gina` | `hank` |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `t0` | `6` | `4` | `3` | `4` | `-` | `-` | `6` | `4` | `0` | `0` | `0` | `0` |
| `t1` | `3` | `4` | `3` | `4` | `-` | `-` | `6` | `4` | `0` | `0` | `0` | `0` |
| `t2` | `3` | `4` | `3` | `4` | `-` | `-` | `6` | `4` | `0` | `0` | `0` | `0` |
| `t3` | `3` | `4` | `3` | `4` | `5` | `2` | `6` | `4` | `0` | `0` | `0` | `0` |
| `t4` | `3` | `4` | `3` | `4` | `5` | `2` | `6` | `4` | `0` | `0` | `0` | `0` |
| `t5` | `3` | `1` | `3` | `1` | `4` | `0` | `6` | `2` | `0` | `0` | `0` | `0` |
| `t6` | `3` | `1` | `3` | `1` | `4` | `0` | `6` | `4` | `5` | `1` | `2` | `3` |

## Slasher `slashableStake(..., 0)`

| Checkpoint | `alice` | `bob` | `carol` | `dave` | `iris` | `jack` | `erin` | `frank` | `gina` | `hank` |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `t0` | `6` | `4` | `3` | `4` | `-` | `-` | `0` | `0` | `0` | `0` |
| `t1` | `3` | `4` | `3` | `4` | `-` | `-` | `0` | `0` | `0` | `0` |
| `t2` | `3` | `4` | `3` | `4` | `-` | `-` | `0` | `0` | `0` | `0` |
| `t3` | `3` | `4` | `3` | `4` | `5` | `2` | `0` | `0` | `0` | `0` |
| `t4` | `3` | `4` | `3` | `4` | `5` | `2` | `0` | `0` | `0` | `0` |
| `t5` | `3` | `1` | `3` | `4` | `4` | `0` | `0` | `0` | `0` | `0` |
| `t6` | `3` | `1` | `3` | `4` | `4` | `0` | `5` | `1` | `2` | `3` |

## What This Shows

1. Multiple operators in multiple networks under one shared subvault:
   - `networkA1` and `networkA2` are both under `sharedSubvaultA`
   - `networkB1` and `networkB2` are both under `sharedSubvaultB`

2. Shared and isolated subvaults before and after each other matter:
   - `isolatedSubvaultX` always takes its `6` first
   - `sharedSubvaultB` is completely starved until the final deposit because it is after `isolatedX`, `sharedA`, and `isolatedY`

3. Partial filling at several levels happens naturally:
   - `t3`: fresh `networkA3` is only partially funded, so `iris = 5`, `jack = 2`
   - `t6`: `sharedB` is funded for `6`, so `networkB1` is partial (`5/1`) while `networkB2` is fully visible (`2/3`)

4. A slash on one network does not automatically reduce sibling slashability:
   - `alice` is slashed at `t1`
   - later at `t2` and `t3`, `bob`, `carol`, and `dave` keep the same public and slashable values they had right after `t1`

5. Fresh networks do not inherit old shared slash credit:
   - `networkA3` is created at `t3`
   - it starts from the current shared baseline only
   - it does not pick up the older shared slash history from `alice`

6. Pending-based preservation expires:
   - `setSize(sharedSubvaultA, 4)` at `t4` creates shared pending
   - before expiry, public sharedA still sits at `7`
   - after expiry at `t5`, public sharedA drops to `4`, so `bob/dave/jack` drop in the public view
   - the slasher view only loses the pending-based part: `bob` drops `4 -> 1`, `jack` drops `2 -> 0`, while `dave` stays at `4` because his remaining preserved guarantee is size-based

7. Later deposits restore the root-funded curve, but only for currently funded order:
   - `t6` restores `isolatedY`
   - `sharedB` finally becomes funded for `6`
   - `sharedA` does not return to `6` because its own durable policy is already `4`
