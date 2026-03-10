# EXAMPLE_SHARED_OVER

This is a valid current `CompactNew` witness showing that an old shared-subvault slash credit can make a fresh network/operator look slashable even though that operator never had positive public `stakeFor()`.

## Scenario

1. `deposit(100)`
2. Create shared `subvault(100)`
3. Create `networkA(100)` under that `subvault`
4. Create `operatorA(100)` under `networkA`
5. Slash `networkA/operatorA` for `80` through `UniversalSlasher`
6. Create fresh `networkB(0)` under the same shared `subvault`
7. Create two operators under `networkB`:
   - `bob(50)`
   - `charlie(50)`
8. `setSize(networkB, 100)`

## State after step 5

- `activeStake = 20`
- public `stakeFor(networkA, operatorA, 0) = 20`
- shared old slash credit exists from the first slash

## Public view after step 8

- `getAllocated(subvault, 0) = 20`
- `getAllocated(networkB, 0) = 20`
- `stakeFor(networkB, bob, 0) = 20`
- `stakeFor(networkB, charlie, 0) = 0`

So `charlie` never had positive public `stakeFor()`.

## Slasher view after step 8

- `slashableStake(networkB, charlie, 0) = 50`

So the fresh operator inherits old shared slash credit and becomes slashable for `50`, even though the public view for that operator is still `0`.

## Execution result

If middleware requests slash for `charlie` using that visible slasher amount:

- `requestSlash(networkB, charlie, 50, ...)` succeeds
- `executeSlash(...)` returns only `20`

So the current logic overstates the fresh operator's slashable amount:

- requested / admitted slashable amount: `50`
- actual realized slash: `20`

## Why this is wrong

The old shared slash credit from `networkA` is being reused by a fresh `networkB` growth.

That means:

1. A newly grown network can inherit slashability it never provided in public `stakeFor()`
2. A fresh operator can become slashable even though its public guarantee was always `0`
3. `slashableStake()` can materially exceed what the shared `subvault` can actually realize for that fresh operator

## Pinned by test

- `test_sharedSubvault_freshNetworkInheritsOldSlashCreditAndOverstatesFreshOperatorSlashableStake`
