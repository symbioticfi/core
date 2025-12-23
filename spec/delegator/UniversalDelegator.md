# Universal Delegator

`UniversalDelegator` is a `BaseDelegator` implementation that allocates a vault’s stake through a small ordered tree of “slots”.
Slots can be configured to allocate **exclusively** (no overlap) or **shared** (overlap / restaking) between siblings.

This document describes the contract behavior in `src/contracts/delegator/UniversalDelegator.sol`.

## Intended depth layout (restaking policy)

The contract enforces fixed roles by depth (`WrongDepth()`):

- Depth `0` (`index = 0`): root, **always not shared**.
- Depth `1`: “group” slots (children of root). Can be `isShared = 1`.
  - Root is not shared, so depth-1 groups are always isolated from each other.
- Depth `2`: network slots (children of a depth-1 group). Can be assigned to `subnetwork` via `assignNetwork`.
  - If the parent group is shared, depth-2 networks **overlap** (restake) between each other.
- Depth `3`: operator slots (children of a depth-2 network). Assigned via `assignOperator`.
  - Depth-2 network slots are never shared, so depth-3 operators are always **isolated** within a network.

## Concepts

### Slot tree

- The tree root is the **implicit slot `index = 0`**.
- Every other slot `index > 0` has a **parent slot** and is stored in `slots[index]`.
- Each slot keeps an **ordered list of children** (`children[]`), so sibling ordering is part of the state.

### Slot indices (`uint96`)

Slot indices are compact paths encoded into a `uint96` (3 × 32-bit segments).
`src/contracts/libraries/UniversalDelegatorIndex.sol` provides helpers:

- `createIndex(parentIndex, localIndex)` creates a child index.
- `getParentIndex(index)` returns the parent index.
- `getDepth(index)` returns `0..3` (`0` only for the root `index=0`).

Practical implications:

- Max depth is **3** (root + 3 levels of slots).
- A slot at depth **3** cannot have children (index encoding has no further segment).

### Slot state

Each slot stores (all checkpointed unless stated):

- `size`: per-slot cap (upper bound on allocation from its parent).
- `prevSum`: prefix sum of *sizes* of earlier siblings (used only when the parent is not shared).
- `isShared`: if `1`, this slot’s **children** can overlap their allocation (restaking between siblings).
- `pendingFreeCumulative`: cumulative “pending free” amount used to delay re-use of freed stake.
- `children[]`: ordered list of `uint32 localIndex` values.
- `childToLocalIndex`: mapping `(childIndex => position in children[])`.

## Allocation model

### Balance vs available

- `getBalance(0)` / `getBalanceAt(0, t)` is the vault’s active stake: `IVault(vault).activeStake()` / `activeStakeAt(t)`.
- For `index > 0`, `getBalance(index)` / `getBalanceAt(index, t)` equals `getAllocated(index)` / `getAllocatedAt(index, t)`:
  the slot’s balance is whatever its parent allocates to it.

“Available” is balance minus stake currently in the “pending free” window:

- `getAvailable(index)` and `getAvailableAt(index, t)` subtract the amount scheduled in the last `IVault(vault).epochDuration()`.

### Child allocation (`getAllocated*`)

Let:

- `parentIndex = index.getParentIndex()`
- `availableParent = getAvailable(parentIndex)` (or `getAvailableAt(parentIndex, t)`)
- `cap = slots[index].size`

In exclusive mode (parent not shared), the child’s effective available is:

- `childAvailable = saturatingSub(availableParent, slots[index].prevSum)`

In shared mode (parent shared), the child’s effective available is:

- `childAvailable = availableParent`

Finally:

- `allocated = min(childAvailable, cap)`

Shared mode means multiple siblings can each reach `allocated == availableParent`, so the **sum of sibling allocations can exceed** the parent’s available stake (restaking/overlap).

## Slot operations

### `createSlot(parentIndex, isShared, size)`

Creates a new child slot under `parentIndex`:

- Appends a new `localIndex` to `slots[parentIndex].children`.
- Initializes the new slot:
  - `prevSum` is set to the current `_getChildrenSize(parentIndex)` (total size of existing children).
  - `isShared` is checkpointed on the new slot.
  - `size` is set to the provided `size`.

`isShared = true` is only allowed when creating a depth-1 slot (i.e., `parentIndex` is the root); otherwise it reverts with `WrongDepth()`.

### `setSize(index, size)`

Updates a slot’s `size` cap.

- Increasing size is only allowed when it doesn’t exceed the parent’s currently unallocated capacity (see `NotEnoughAvailable()`).
- Decreasing size below the slot’s current allocation schedules a “pending free” amount on the parent via `pendingFreeCumulative`.
- Updates `prevSum` checkpoints for following siblings using `_syncPrevSums(index)`.

### `swapSlots(index1, index2)`

Reorders two sibling slots under the same parent.

Constraints:

- Must share the same parent (`NotSameParent()`).
- `index1` must currently appear before `index2` (`WrongOrder()`).
- Both slots must be either allocated or unallocated at the parent level (`NotSameAllocated()`).
- Reverts if the later slot is partially allocated (`PartiallyAllocated()`).

After swapping:

- Updates the parent’s `children[]` order and `childToLocalIndex`.
- Pushes a new `prevSum` checkpoint for the moved slot and calls `_syncPrevSums` to update following siblings.

### `setIsShared(index, isShared)`

Toggles whether a slot’s **children** allocate in shared mode.

Rules:

- Only depth-1 slots can be toggled (`WrongDepth()`), so the root (`index = 0`) is always not shared.
- No-op toggles revert (`IsSharedNotChanged()`).
- For `index > 0`, the slot itself must have zero allocation from its parent (`SlotAllocated()`).

## Network and operator assignment

### Networks

`assignNetwork(index, subnetwork)` assigns a `bytes32 subnetwork` to a slot:

- `index` must be at depth 2 (`WrongDepth()`).
- A subnetwork can only be assigned once (`NetworkAlreadyAssigned()`).

`unassignNetwork(subnetwork)` clears the assignment:

- Reverts if not assigned (`NetworkNotAssigned()`).
- Reverts if the slot still has allocation (`SlotAllocated()`).

The active slot for a subnetwork is stored historically via `networkToSlot[subnetwork]` checkpoints.

### Operators

Operators are assigned *under a specific parent slot* (typically the network’s slot) using:

- `assignOperator(index, operator)`

Constraints:

- `index` must be at depth 3 (`WrongDepth()`).
- The operator must not already be assigned under that parent (`OperatorAlreadyAssigned()`).

Unassignment:

- `unassignOperator(parentIndex, operator)` requires the operator’s slot to have zero allocation (`SlotAllocated()`), then clears the mapping.

Operator assignment is tracked historically via `operatorToSlot[parentIndex][operator]` checkpoints.

## Restaking detection

`isRestaked(subnetwork, operator)` and `isRestakedAt(subnetwork, operator, t, ...)` return `true` when the operator’s slot has any **shared ancestor**:

- Walks up from the operator slot’s parent to the root.
- Returns `true` if any `slots[ancestor].isShared` is `1`.

With the enforced depth policy, this means “restaked” is effectively “the operator’s network slot (depth 2) is under a shared group slot (depth 1)”.

## Hints

Some `*At(...)` view functions accept `bytes hints` to speed up checkpoint lookups.

`stakeAt(...)` expects `hints` to be ABI-encoded as:

```solidity
IUniversalDelegator.StakeHints({
    baseHints: /* hints forwarded to BaseDelegator opt-in checks */,
    allocatedHints: /* hints forwarded into allocation lookups */
});
```

`UniversalDelegator` uses `allocatedHints` across multiple checkpoint traces. If you are not certain hints match the queried trace, pass empty bytes (`""`) to avoid reverts.

## Caveats

- `BaseDelegator.maxNetworkLimit` is currently not enforced by `UniversalDelegator` (`_setMaxNetworkLimit` is empty).

## Minimal examples

### Isolated groups (no restaking across depth 1)

```solidity
// Create two depth-1 groups under root (root is not shared).
createSlot(0, false, type(uint256).max); // index: g1
createSlot(0, false, type(uint256).max); // index: g2
```

### Restaking between networks within a group (shared depth 1)

```solidity
// Create a shared depth-1 group.
createSlot(0, true, type(uint256).max); // index: g

// Create depth-2 networks under the shared group and assign subnetworks.
createSlot(g, false, 1_000e18);          // index: n1
createSlot(g, false, 1_000e18);          // index: n2
assignNetwork(n1, subnetwork1);
assignNetwork(n2, subnetwork2);

// Create depth-3 operator slots under each network and assign operators.
createSlot(n1, false, 600e18);           // index: o1
assignOperator(o1, alice);
createSlot(n2, false, 600e18);           // index: o2
assignOperator(o2, bob);
```
