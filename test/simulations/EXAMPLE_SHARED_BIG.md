> Amounts are shown in whole tokens (1 token = 1e18).
> Epoch duration: `3 days`.
> This is a larger illustrative example for the current production `UniversalDelegator` shared-subvault behavior.
> It focuses on `stakeFor(..., 0)` and `slashableStake(..., 0)` only.

## Core Idea

For shared subvaults under the current production contract:

1. public `stakeFor()` is the real-time funded view
2. later shared networks can still inherit current shared baseline without inheriting older pre-creation credit
3. shared pending by itself does not create sibling-network guarantee
4. pending expiry still changes the public curve inside the subtree
5. shared size-based preservation is now epoch-windowed too

## Root Order

The root has four children in this exact order:

1. `isolatedSubvaultX(6)`
2. `sharedSubvaultA(10)`
3. `isolatedSubvaultY(4)`
4. `sharedSubvaultB(8)`

That order drives the root-funded curve.

## Local Layout

### `isolatedSubvaultX`

- `networkX(8)`
- `xavier(6)`

### `sharedSubvaultA`

- `networkA1(12)`
  - `alice(6)`
  - `bob(4)`
- `networkA2(8)`
  - `carol(3)`
  - `dave(4)`
- later: `networkA3(8)`
  - `iris(5)`
  - `jack(5)`

### `isolatedSubvaultY`

- `networkY(5)`
- `yves(4)`

### `sharedSubvaultB`

- `networkB1(6)`
  - `erin(5)`
  - `frank(3)`
- `networkB2(7)`
  - `gina(2)`
  - `hank(3)`

## Scenario Sequence

1. Create all root subvaults in the order above.
2. Create all listed networks and operators except `networkA3`.
3. `deposit(20)`
4. Slash `networkA1/alice` by `3`
5. `withdraw(5)`
6. Create fresh `networkA3(8)` with `iris(5)` and `jack(5)`
7. Create pending at three depths in the same subtree:
   - `setSize(sharedSubvaultA, 4)`
   - `setSize(networkA2, 4)`
   - `setSize(dave, 2)`
8. While that pending is still active, `withdraw(2)`
9. `wait(epoch + 1s)` so that both the pending and the withdrawal window expire
10. `deposit(8)`

## Root-Funded Subvault Curve

| Checkpoint                                              | `activeStake` | `activeWithdrawalsFor(0)` | `isolatedX` funded | `sharedA` funded | `isolatedY` funded | `sharedB` funded |
| ------------------------------------------------------- | ------------: | ------------------------: | -----------------: | ---------------: | -----------------: | ---------------: |
| `t0` after `deposit(20)`                                |          `20` |                       `0` |                `6` |             `10` |                `4` |              `0` |
| `t1` after slash `A/alice = 3`                          |          `17` |                       `0` |                `6` |              `7` |                `4` |              `0` |
| `t2` after first `withdraw(5)`                          |          `12` |                       `5` |                `6` |              `7` |                `4` |              `0` |
| `t3` after fresh `networkA3`                            |          `12` |                       `5` |                `6` |              `7` |                `4` |              `0` |
| `t4` after pending-creating `setSize(...)` calls        |          `12` |                       `5` |                `6` |              `7` |                `4` |              `0` |
| `t4w` after extra `withdraw(2)` while pending is active |          `10` |                       `7` |                `6` |              `7` |                `4` |              `0` |
| `t5` after pending and withdrawals expire               |          `10` |                       `0` |                `6` |              `4` |                `0` |              `0` |
| `t6` after `deposit(8)`                                 |          `18` |                       `0` |                `6` |              `4` |                `4` |              `4` |

## Public `stakeFor(..., 0)`

| Checkpoint | `alice` | `bob` | `carol` | `dave` | `iris` | `jack` | `xavier` | `yves` | `erin` | `frank` | `gina` | `hank` |
| ---------- | ------: | ----: | ------: | -----: | -----: | -----: | -------: | -----: | -----: | ------: | -----: | -----: |
| `t0`       |     `6` |   `4` |     `3` |    `4` |    `-` |    `-` |      `6` |    `4` |    `0` |     `0` |    `0` |    `0` |
| `t1`       |     `3` |   `4` |     `3` |    `4` |    `-` |    `-` |      `6` |    `4` |    `0` |     `0` |    `0` |    `0` |
| `t2`       |     `3` |   `4` |     `3` |    `4` |    `-` |    `-` |      `6` |    `4` |    `0` |     `0` |    `0` |    `0` |
| `t3`       |     `3` |   `4` |     `3` |    `4` |    `5` |    `2` |      `6` |    `4` |    `0` |     `0` |    `0` |    `0` |
| `t4`       |     `3` |   `4` |     `3` |    `4` |    `5` |    `2` |      `6` |    `4` |    `0` |     `0` |    `0` |    `0` |
| `t4w`      |     `3` |   `1` |     `2` |    `1` |    `4` |    `0` |      `6` |    `4` |    `0` |     `0` |    `0` |    `0` |
| `t5`       |     `3` |   `1` |     `2` |    `2` |    `4` |    `0` |      `6` |    `0` |    `0` |     `0` |    `0` |    `0` |
| `t6`       |     `3` |   `1` |     `2` |    `2` |    `4` |    `0` |      `6` |    `4` |    `4` |     `0` |    `2` |    `2` |

## Slasher `slashableStake(..., 0)`

| Checkpoint | `alice` | `bob` | `carol` | `dave` | `iris` | `jack` | `erin` | `frank` | `gina` | `hank` |
| ---------- | ------: | ----: | ------: | -----: | -----: | -----: | -----: | ------: | -----: | -----: |
| `t0`       |     `6` |   `4` |     `3` |    `4` |    `-` |    `-` |    `0` |     `0` |    `0` |    `0` |
| `t1`       |     `3` |   `4` |     `3` |    `4` |    `-` |    `-` |    `0` |     `0` |    `0` |    `0` |
| `t2`       |     `3` |   `4` |     `3` |    `4` |    `-` |    `-` |    `0` |     `0` |    `0` |    `0` |
| `t3`       |     `3` |   `4` |     `3` |    `4` |    `5` |    `2` |    `0` |     `0` |    `0` |    `0` |
| `t4`       |     `3` |   `4` |     `3` |    `4` |    `5` |    `2` |    `0` |     `0` |    `0` |    `0` |
| `t4w`      |     `3` |   `4` |     `3` |    `4` |    `5` |    `2` |    `0` |     `0` |    `0` |    `0` |
| `t5`       |     `3` |   `1` |     `2` |    `2` |    `4` |    `0` |    `0` |     `0` |    `0` |    `0` |
| `t6`       |     `3` |   `1` |     `2` |    `2` |    `4` |    `0` |    `4` |     `0` |    `2` |    `2` |

## Pending `getPending(..., 0)`

The big scenario now includes pending at three levels inside `sharedSubvaultA`.

| Checkpoint | `sharedA` pending | `networkA2` pending | `dave` pending |
| ---------- | ----------------: | ------------------: | -------------: |
| `t0`       |               `0` |                 `0` |            `0` |
| `t1`       |               `0` |                 `0` |            `0` |
| `t2`       |               `0` |                 `0` |            `0` |
| `t3`       |               `0` |                 `0` |            `0` |
| `t4`       |               `3` |                 `3` |            `2` |
| `t4w`      |               `3` |                 `3` |            `2` |
| `t5`       |               `0` |                 `0` |            `0` |
| `t6`       |               `0` |                 `0` |            `0` |

## What This Shows

1. Multiple operators in multiple networks under one shared subvault:

   - `networkA1`, `networkA2`, and later `networkA3` all live under `sharedSubvaultA`
   - `networkB1` and `networkB2` both live under `sharedSubvaultB`

2. Shared and isolated subvaults before and after each other matter:

   - `isolatedSubvaultX` always takes its `6` first
   - `sharedSubvaultB` is completely starved until the final deposit because it sits after `isolatedX`, `sharedA`, and `isolatedY`

3. Partial filling at several levels happens naturally:

   - network caps are no longer equal to the sum of operator caps
   - some networks have slack (`networkX`, `networkA1`, `networkA2`, `networkY`, `networkB2`)
   - some networks are overcommitted by operators (`networkA3`, `networkB1`)
   - `t3`: fresh `networkA3` is only partially funded, so `iris = 5`, `jack = 2`
   - `t6`: `sharedB` is funded for `4`, so `networkB1` is partial (`erin = 4`, `frank = 0`) while `networkB2` is also partial (`gina = 2`, `hank = 2`)

4. A fresh network created after an earlier shared slash starts from the current shared baseline:

   - `networkA3` appears only at `t3`
   - it is funded from the then-current `sharedA` balance
   - it does not pick up any older pre-creation shared history before `t3`

5. The big scenario now shows pending at multiple depths in one shared subtree:

   - `sharedA` has subvault-level pending `3` at `t4`
   - `networkA2` has network-level pending `3` at `t4`
   - `dave` has operator-level pending `2` at `t4`
   - all three are still present at `t4w`, even after a new withdrawal
   - all three expire together by `t5`

6. Withdrawals can coexist with those pending slots in the same window:

   - `t4w` adds another withdrawal while shared/network/operator pending is still live
   - `activeWithdrawalsFor(0)` becomes `7`
   - public funding drops immediately (`bob: 4 -> 1`, `carol: 3 -> 2`, `dave: 4 -> 1`, `jack: 2 -> 0`)
   - slasher/public divergence still remains during that window in this scenario (`bob/dave/iris/jack` stay at `4/4/5/2`, while `carol` stays `3`)
   - this does not mean shared pending itself became sibling guarantee; the preserved difference here comes from the existing shared-size path plus ordinary local pending/public allocation

7. After the epoch window, shared slasher visibility collapses back to public for this subtree:

   - after `t5`, `bob` in the slashed `networkA1` drops to `1 / 1`
   - `carol` and `dave` in the unslashed `networkA2` settle to `2 / 2`
   - `jack` drops from `0 / 2` at `t4w` to `0 / 0` at `t5`

8. Shared effects before the epoch boundary are still network-scoped in this scenario:
   - the slashed `networkA1` does not get its own shared-size effect back
   - the unslashed `networkA2` keeps the preserved slashability before `t5`
   - `sharedB` behaves like an ordinary later subtree once the root curve reaches it again at `t6`
