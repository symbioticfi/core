# ISSUES

Generated: 2026-03-02 08:36:29 +04

- Raw findings: 36
- Unique issues after deduplication: 33
- Deduplication rule: normalized title (case-insensitive, punctuation/backticks removed).

## 1. [High] Network can nullify pending slash requests via resetAllocation

- IDs: 9
- Sources: FINDINGS2.json
- Affected: src/contracts/delegator/UniversalDelegator.sol:737-795

### Description

> A network or its middleware can call `resetAllocation()` during the veto period of a pending slash request to remove the operator's slot from the UniversalDelegator. When `executeSlash` later checks `slashableStake()`, it calls `stakeFor(subnetwork, operator, 0)` which calls `getAllocated(subnetwork, operator, 0)`. Since the slot was removed by `resetAllocation`, `getSlotOf()` returns 0 and `getAllocated` returns 0, causing `executeSlash` to revert with `InsufficientSlash()`. This allows networks to escape valid slashing obligations.

### Impact

> A network can deliberately avoid any slash by calling `resetAllocation` before `executeSlash` is called. This completely undermines the slashing mechanism, as operators that should be economically penalized can collude with networks to avoid all slashes. Since `resetAllocation` is callable by the network directly (not just middleware), even non-middleware network actors can trigger this escape.

### Recommendation

> Implement a mechanism to prevent `resetAllocation` from being effective while there are pending slash requests for that subnetwork. For example, add a cooldown period after a slash request is created during which `resetAllocation` is blocked, or snapshot allocations at slash request creation time.

---

## 2. [High] Withdrawal requests can be repriced at the unlock boundary during slashing

- IDs: 9675937e-5e97-4ea1-87a0-7582ae94e4ba
- Sources: FINDINGS1.json
- Status: review
- Accepted: true

### Description

> Lines:
>
> - [src/contracts/vault/VaultV2.sol#L208](https://github.com/symbioticfi/core-mirror/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/vault/VaultV2.sol#L208)
>
> `VaultV2.withdrawalsOf()` resolves a request using `_unlockToBucket.upperLookupRecent(withdrawalUnlockAfter(index, account))`, while `VaultV2.claim()` enforces `block.timestamp <= withdrawalUnlockAfter(...)` as not matured. At `block.timestamp == unlockAfter`, the request is still not claimable, but `VaultV2.onSlash()` can update withdrawal bucket state at the same timestamp. This allows a pre-existing request to be remapped into a newer bucket at the boundary and repriced.
>
> Impact: Withdrawal valuation may drift from intended bucket semantics at the unlock boundary. A claimant may receive more than expected after later donations, which may shift value from other participants or future inflows. The same state may also produce temporary claim failures.

### Recommendation

> We recommend aligning request valuation so a request cannot be remapped at `unlockAfter`.
>
> ```diff
> - uint256 bucketIndex = _unlockToBucket.upperLookupRecent(withdrawalUnlockAfter(index, account));
> + uint48 unlockAfter_ = withdrawalUnlockAfter(index, account);
> + uint48 lookupTimestamp = unlockAfter_ > 0 ? unlockAfter_ - 1 : 0;
> + uint256 bucketIndex = _unlockToBucket.upperLookupRecent(lookupTimestamp);
> }
> ```

---

## 3. [Medium] If an operator in a shared subvault is slashed, every operator in the subvault is affected

- IDs: bc9462a4-b610-4a43-a7a5-e78fe41deb0e
- Sources: FINDINGS3.json
- Status: draft
- Accepted: true

### Description

> Line:
>
> In `UniversalDelegator.onSlash()`, the slash loop walks the full parent chain from the targeted operator slot up to the root, decrementing the size of every slot along the way.
>
> When the targeted operator's slot is fully slashed, the full slash amount propagates up and removes the same quantity from the parent network slot and then from the grandparent subvault slot. For a shared subvault this is problematic, because every sibling operator's effective allocation is derived from the subvault's size via `UniversalDelegator.getAllocated()`.
>
> Consider the following concrete scenario. A shared subvault has size = 10. Two operators are registered under the same network inside that subvault, each with size = 10. Operator 1 is slashed for 10: its slot size becomes 0, the network slot size becomes 0, and the subvault slot size becomes 0. Operator 2's slot still records size = 10, but getAllocated for operator 2 now evaluates min(0, 10) = 0, so operator 2 reports zero stake even though it was never slashed.

### Recommendation

> Consider separating the slash accounting at the subvault level so that reducing the slashed operator's contribution does not reduce the subvault's aggregate capacity for other operators. One approach is to track, per subvault, the total size contributed by each operator independently, and only reduce the subvault's effective ceiling by the amount that belonged to the slashed operator. Alternatively, the subvault size could be treated as a cap that is not itself decremented on a slash; instead, only the individual operator slot and the network slot that maps directly to the slashed operator would absorb the reduction.

---

## 4. [Medium] Non-Zero size persists after slot removal

- IDs: f4918246-658c-4269-97e8-77ac05dec352
- Sources: FINDINGS3.json
- Status: review
- Accepted: true

### Description

> Lines:
>
> - [UniversalDelegator.sol#L687-L706](https://github.com/symbioticfi/core-mirror/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/delegator/UniversalDelegator.sol#L687-L706)
> - [UniversalDelegator.sol#L709-L735](https://github.com/symbioticfi/core-mirror/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/delegator/UniversalDelegator.sol#L709-L735)
>
> When a slot is removed, for example, a subvault slot, the slot is marked as non-existent; however, its size is not set to zero. This can cause phantom allocation in children of the subvault (operators and networks). For example, `UniversalDelegator.stakeFor(subnetwork, operator, 0)` will return a non-zero value, although the slot in which they exist no longer exists. Additionally, when a subvault is removed, mappings `_networkToSlot` and `_slotToNetwork` are not cleared.
>
> This can happen in the following sequence:
>
> 1. `activeStake = 200`, `subvault1.size = 100`, `subvault2.size = 100`
> 2. `subvault2` cannot be removed because `UniversalDelegator.getAllocated(index, 0) > 0` check
> 3. A user withdraws `100` from Vault, so `activeStake = 100` while both subvault sizes remain unchanged
> 4. Now `UniversalDelegator.getAllocated(subvault2, 0) = 0`, so `UniversalDelegator.removeSlot(subvault2)` becomes allowed
> 5. Later, someone deposits `100` back and `activeStake = 200`. The `getAllocated(subvault2, 0)` will return previous saved size. It creates phantom allocation.
>
> This may lead to unexpected behavior. For example, `UniversalSlasher.requestSlash(subnetwork, operator, amount, hints)` can be called for an operator whose subvault was removed. Additionally, `UniversalDelegator.stakeFor()` and related allocation getters may return values that are inconsistent.

### Recommendation

> We recommend zeroing the removed slot's size and clean up descedant links and key mappings (`_networkToSlot`, `_slotToNetwork`, `_operatorToSlot`, `_slotToOperator`).

---

## 5. [Medium] Pending calculation underreports when a clearing event outlives its corresponding pending in the time window

- IDs: 95c69c84-548b-46ac-b67b-a1f2b8e6efd7
- Sources: FINDINGS3.json
- Status: draft
- Accepted: true

### Description

> Lines:
>
> - [UniversalDelegator.sol#L236-L251](https://github.com/symbioticfi/core-mirror/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/delegator/UniversalDelegator.sol#L236-L251)
> - [UniversalDelegator.sol#L256-L270](https://github.com/symbioticfi/core-mirror/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/delegator/UniversalDelegator.sol#L256-L270)
> - [UniversalDelegator.sol#L275-L291](https://github.com/symbioticfi/core-mirror/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/delegator/UniversalDelegator.sol#L275-L291)
> - [UniversalDelegator.sol#L295-L307](https://github.com/symbioticfi/core-mirror/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/delegator/UniversalDelegator.sol#L295-L307)
> - [UniversalDelegator.sol#L976-L987](https://github.com/symbioticfi/core-mirror/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/delegator/UniversalDelegator.sol#L976-L987)
> - [UniversalDelegator.sol#L824-L846](https://github.com/symbioticfi/core-mirror/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/delegator/UniversalDelegator.sol#L824-L846)
> - [UniversalDelegator.sol#L330-L336](https://github.com/symbioticfi/core-mirror/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/delegator/UniversalDelegator.sol#L330-L336)
> - [UniversalDelegator.sol#L469-L470](https://github.com/symbioticfi/core-mirror/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/delegator/UniversalDelegator.sol#L469-L470)
>
> [UniversalDelegator.getPendingAt()](https://github.com/symbioticfi/core-mirror/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/delegator/UniversalDelegator.sol#L275-L291) and [UniversalDelegator.getPending()](https://github.com/symbioticfi/core-mirror/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/delegator/UniversalDelegator.sol#L295-L307) compute active pending as a subtraction between independent windowed cumulative deltas (`pendingCumulative` minus `clearedPendingCumulative`). The same pattern is used in [UniversalDelegator.getChildrenPendingAt()](https://github.com/symbioticfi/core-mirror/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/delegator/UniversalDelegator.sol#L236-L251), [UniversalDelegator.getChildrenPending()](https://github.com/symbioticfi/core-mirror/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/delegator/UniversalDelegator.sol#L256-L270), and [UniversalDelegator.\_getNoPluginsPending()](https://github.com/symbioticfi/core-mirror/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/delegator/UniversalDelegator.sol#L976-L987). When a pending amount is created at `T_add` and cleared at `T_clear`, and the query window later satisfies `T_add < fromTimestamp <= T_clear`, the add event may already be outside the window while the clear event is still inside it. This causes the clear delta to offset unrelated newer pending entries, so the reported pending can be lower than the true active pending.
>
> Underreporting from [UniversalDelegator.getPending()](https://github.com/symbioticfi/core-mirror/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/delegator/UniversalDelegator.sol#L295-L307) propagates into [UniversalDelegator.onSlash()](https://github.com/symbioticfi/core-mirror/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/delegator/UniversalDelegator.sol#L815-L846), where `pendingSlashed` is capped by the reported pending before the remainder is applied to `size`, which may over-reduce slot size relative to intended pending clearance.
>
> Underreporting from [UniversalDelegator.getChildrenPending()](https://github.com/symbioticfi/core-mirror/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/delegator/UniversalDelegator.sol#L256-L270) feeds into [UniversalDelegator.getAvailable()](https://github.com/symbioticfi/core-mirror/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/delegator/UniversalDelegator.sol#L335-L336), which may overstate parent availability.
>
> Underreporting from [UniversalDelegator.\_getNoPluginsPending()](https://github.com/symbioticfi/core-mirror/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/delegator/UniversalDelegator.sol#L976-L987) feeds into [UniversalDelegator.getNoPluginsSize()](https://github.com/symbioticfi/core-mirror/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/delegator/UniversalDelegator.sol#L469-L470), which may understate reserved no-plugins capacity.

### Recommendation

> The root cause is that the amount being cleared is “timestamped” at `T_add`, but the clear itself is recorded at
> `T_clear`. With a rolling window, it’s possible for `T_add` to fall outside `fromTimestamp` while `T_clear` is still
> inside it, so a windowed `adds - clears` calculation can subtract clears that belong to already-expired adds.
>
> A robust fix requires attributing clears to the same time basis as adds. Practical approaches:
>
> - Track pending as a FIFO queue of `(timestamp, amount)` per slot (and an aggregate sum). On slash, consume from the
>   oldest entries; on any state-changing call, prune entries older than the slashing window. This guarantees a clear
>   cannot “outlive” the pending it clears.
> - If you want bounded storage, bucket pending by time (e.g., per-epoch or per-N-second buckets) and consume buckets
>   FIFO, so clearing is applied to the same buckets that created the pending.
>
> Avoid fixes that only compare “adds-in-window” to “lifetime net pending” (e.g., `min(windowAdds, totalAdds-totalClears)`):
> they will fail to subtract clears that legitimately apply to in-window adds and can overstate pending.

---

## 6. [Medium] Stale `prevSum` in withdrawal buffer after last subvault removal

- IDs: 487060cb-94ae-42cb-a814-a27ee50a4c52
- Sources: FINDINGS3.json
- Status: draft
- Accepted: true

### Description

> Lines: [UniversalDelegator.sol#L719-L737](https://github.com/symbioticfi/core-mirror/blob/cc21dbb9c30a216be4f8c818b4089595c4c1789b/src/contracts/delegator/UniversalDelegator.sol#L719-L737).
>
> When `UniversalDelegator._removeSlot()` removes the last subvault under root, it sets `root.firstChild` to `0` (because the only next child is `WITHDRAWAL_BUFFER_CHILD_INDEX`). This removes the withdrawal buffer from subsequent `_syncPrevSums(0)` traversal. The same function does not refresh the withdrawal buffer `prevSum` and does not set `root.needPrevSumsSync` for this transition.
>
> This state can be reached through direct `removeSlot()` calls, and also through `resetAllocation()` when it collapses to the parent subvault (`existChildren == 1`) and then calls `_removeSlot()` on that last root subvault.
>
> As a result, after `removeSlot()` succeeds on the last root subvault, `_getPrevSum(WITHDRAWAL_BUFFER_INDEX)` can read a stale checkpoint value while `needPrevSumsSync == 0`. Later, if vault balance increases, `getWithdrawalBuffer()` can stay artificially reduced because `getAllocated(WITHDRAWAL_BUFFER_INDEX, 0)` subtracts that stale `prevSum`.
>
> Impact: `VaultV2.instantWithdraw()` caps withdrawals using `getWithdrawalBuffer()` ([VaultV2.sol#L343-L345](https://github.com/symbioticfi/core-mirror/blob/cc21dbb9c30a216be4f8c818b4089595c4c1789b/src/contracts/vault/VaultV2.sol#L343-L345)). A stale withdrawal-buffer `prevSum` can reduce instant-withdraw capacity below intended availability until another root-child operation re-syncs state.

### Recommendation

> We recommend updating `_removeSlot()` to re-sync withdrawal-buffer prefix state when removing the last root subvault. One practical fix is to set `root.needPrevSumsSync` in that branch, or explicitly push `0` to the withdrawal buffer `prevSum` checkpoint.
>
> ```diff
>     if (index.getChildIndex() == parent.firstChild.latest()) {
>         uint32 nextChildIndex = uint32(slot.nextSlot.latest());
>         parent.firstChild.push(
>             uint48(block.timestamp),
>             index.getDepth() > 1 || nextChildIndex < WITHDRAWAL_BUFFER_CHILD_INDEX ? nextChildIndex : 0
>         );
> +       if (index.getDepth() == 1 && nextChildIndex == WITHDRAWAL_BUFFER_CHILD_INDEX) {
> +           slots[index.getParentIndex().createIndex(WITHDRAWAL_BUFFER_CHILD_INDEX)].prevSum.push(
> +               uint48(block.timestamp), 0
> +           );
> +       }
>     }
> ```

---

## 7. [Medium] UniversalDelegator createSlot does not validate subnetwork against network registry

- IDs: 47
- Sources: FINDINGS2.json
- Affected: src/contracts/delegator/UniversalDelegator.sol:511-516

### Description

> When creating a depth-2 slot (network slot under a subvault), `_createSlot` assigns `_networkToSlot[subnetworkOrOperator]` without verifying that the subnetwork's network component is registered in the `NETWORK_REGISTRY`. Any arbitrary `bytes32` value can serve as the subnetwork identifier.
>
> ```solidity
> if (parentIndex.getDepth() == 1) {
>     if (_networkToSlot[subnetworkOrOperator].latest() > 0) {
>         revert AlreadyAssigned();
>     }
>     _networkToSlot[subnetworkOrOperator].push(uint48(block.timestamp), index);
>     _slotToNetwork[index] = subnetworkOrOperator;
> }
> ```

### Impact

> A curator can create network slots for non-existent or deregistered networks. Vault funds get allocated to invalid subnetworks, wasting allocation capacity. While the slasher's middleware check prevents unauthorized slashing, the allocated stake cannot be productively used or properly slashed, effectively locking it away from legitimate networks.

### Recommendation

> Add a validation check: `if (!IRegistry(NETWORK_REGISTRY).isEntity(subnetworkOrOperator.network())) revert InvalidNetwork();` before creating the network slot.

---

## 8. [Medium] User funds are not slashable and not claimable when `block.timestamp == unlockAfter`

- IDs: 18aa0559-672f-4615-86b9-a91b887f0f2a
- Sources: FINDINGS1.json
- Status: review
- Accepted: true

### Description

> Lines:
>
> - [VaultV2.sol#L381](https://github.com/symbioticfi/core-mirror/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/vault/VaultV2.sol#L381)
> - [VaultV2.sol#L445](https://github.com/symbioticfi/core-mirror/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/vault/VaultV2.sol#L445)
>
> When `block.timestamp == unlockAfter`, the withdrawal enters an inconsistent state. The user cannot claim the funds, and the funds are not slashable. This happens because `VaultV2.activeWithdrawals()` excludes the withdrawal from slashing, while `VaultV2.claim()` uses a `<=` check that still rejects claims at that exact timestamp.
>
> The withdrawal should be slashable or claimable. There should be no inconsistent state. Due to NatSpec in the [IVaultV2.sol](https://github.com/symbioticfi/core-mirror/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/interfaces/vault/IVaultV2.sol#L492), the withdrawal must be claimable.

### Recommendation

> We recommend changing the condition from `<=` to `<` so that the withdrawal becomes claimable:
>
> ```solidity
> if (block.timestamp < withdrawalUnlockAfter(index, msg.sender)) {
>     revert WithdrawalNotMatured();
> }
> ```

---

## 9. [Medium] `removeSlot` does not zero slot size on removal

- IDs: ed7e783c-ba6f-4172-b30a-78168099da45
- Sources: FINDINGS3.json
- Status: draft
- Accepted: true

### Description

> Lines: [UniversalDelegator.sol#L692-L710](https://github.com/symbioticfi/core-mirror/blob/cc21dbb9c30a216be4f8c818b4089595c4c1789b/src/contracts/delegator/UniversalDelegator.sol#L692-L710)
>
> `UniversalDelegator.removeSlot()` removes only the passed `index` from the linked list and clears only that slot's direct assignment (`_slotToNetwork[index]` or `_slotToOperator[index]`). It does not recursively clear descendant mappings when removing a parent with existing children. `UniversalDelegator._removeSlot()` also sets only `slots[index].exists = false` and does not clear `slots[index].size`.
>
> Because `UniversalDelegator.getAllocated()` does not check `slots[index].exists` and still uses `slots[index].size.latest()`, removed slots can continue to report non-zero allocation after vault balance conditions change.
>
> This propagates to `UniversalDelegator.getBalance()` and `UniversalDelegator.getAvailable()` for `index > 0` because they are wrappers over `getAllocated()` / `getAllocatedAt()`.
>
> More importantly, `UniversalDelegator.stakeAt()` can also return a non-zero value for orphaned slots in post-migration windows (`timestamp >= __migrateTimestamp`), because it calls `getAllocatedAt(subnetwork, operator, epochDuration, timestamp)`, which resolves index via `getSlotOfAt(...)` and then uses slot `size` without an existence check.
>
> When a removed parent leaves descendant mappings reachable (for example, a removed subvault leaves `_networkToSlot[subnetwork]` and downstream operator mapping entries intact), `UniversalDelegator.getSlotOf(subnetwork, operator)` can still resolve to an orphaned operator slot. `UniversalDelegator.onSlash()` then iterates and mutates state along that orphaned chain without validating `slot.exists`, including slashing `slot.size` on orphaned slots.
>
> `UniversalSlasher.slashableStake()` consumes delegator stake values and can therefore return non-zero for the same orphaned mapping path. For `captureTimestamp == 0` (the path used by `requestSlash()`), it returns `stakeFor(...)`. For legacy captures (`captureTimestamp < __migrateTimestamp`), it uses `stakeAt(...)`.
>
> Because `requestSlash()` only reverts when `slashableStake == 0`, stale non-zero values allow creating slash requests on removed/orphaned topology. `executeSlash()` re-checks with `slashableStake(...)`, and if still non-zero, it calls both `UniversalDelegator.onSlash(...)` and `VaultV2.onSlash(...)`.
>
> Impact: This escalates the issue from a view/accounting inconsistency to an economic effect. Removed topology can remain slash-reachable, and stale non-zero stake readings can produce non-zero `slashableStake`, enabling slash execution that reduces vault stake/withdrawals through `VaultV2.onSlash()` even though the slot hierarchy was removed from active topology.

### Recommendation

> We recommend zeroing `slots[index].size` inside `removeSlot()`, and enforcing recursive cleanup for descendants on parent removal, including clearing descendant `_networkToSlot` and `_operatorToSlot` entries.
>
> ```diff
>     if (_slotToNetwork[index] != bytes32(0)) {
>         _networkToSlot[_slotToNetwork[index]].push(uint48(block.timestamp), 0);
>         _slotToNetwork[index] = bytes32(0);
>     } else if (_slotToOperator[index] != address(0)) {
>         _operatorToSlot[index.getParentIndex()][_slotToOperator[index]].push(uint48(block.timestamp), 0);
>         _slotToOperator[index] = address(0);
>     }
>
> +    uint208 slotSize = slots[index].size.latest();
> +    if (slotSize > 0) {
> +        slots[index].size.push(uint48(block.timestamp), 0);
> +        slots[index.getParentIndex()].needPrevSumsSync.push(uint48(block.timestamp), 1);
> +    }
>
>     _removeSlot(index);
> ```

---

## 10. [Medium] `resetAllocation` does not clean up child operator slot state when removing entire subvault (existChildren == 1)

- IDs: 1
- Sources: FINDINGS2.json
- Affected: src/contracts/delegator/UniversalDelegator.sol:756-758,790-791

### Description

> In `UniversalDelegator.resetAllocation()` (lines 737-795), when `slots[index.getParentIndex()].existChildren == 1`, the function moves `index` up to the parent subvault and removes the subvault. However, operator slots that were children of the network slot are NOT cleaned up. Their `_operatorToSlot[networkIndex][operator]` mappings remain pointing to the operator slot indices, and `slots[operatorIndex].exists` remains `true`. The network slot under the removed subvault also retains `exists = true` and its size.
>
> Specifically at line 756-758:
>
> ```
> if (slots[index.getParentIndex()].existChildren == 1) {
>     index = index.getParentIndex();
> }
> ```
>
> After this, only the subvault slot is cleaned up and removed. The network slot's `_slotToNetwork` was cleared at line 754, but operator slots remain with stale state.

### Impact

> Orphaned operator slots with `exists = true` can still be targeted by `setSize()`, `swapSlots()`, and `removeSlot()` functions since they pass the `slotExists` modifier. While these require privileged roles (SET_SIZE_ROLE, etc.), the stale `_operatorToSlot` mappings represent an inconsistent state that could confuse off-chain integrations querying `getSlotOfOperator()` directly with the old network index. The orphaned slots' sizes permanently consume checkpoint storage without cleanup.

### Recommendation

> When `existChildren == 1` and the subvault is being removed, iterate over the network slot's operator children to clear their `_operatorToSlot` mappings, `_slotToOperator` mappings, and set `exists = false`. Alternatively, perform recursive cleanup of all child slots when removing a parent, or document that the REMOVE_SLOT_ROLE holder must clean up children manually before `resetAllocation`.

---

## 11. [Medium] removeSlot does not decrement \_noPluginsSize for noPlugins subvault slots

- IDs: 2
- Sources: FINDINGS2.json
- Affected: src/contracts/delegator/UniversalDelegator.sol:684,685,686,687,688,689,690,691,692,693,694,695,696,697,698,699,700,701,702,703

### Description

> In UniversalDelegator.removeSlot(), when removing a depth-1 subvault slot that has noPlugins=true and size>0, the \_noPluginsSize state variable is not decremented. Compare with resetAllocation() (lines 785-787) which properly decrements \_noPluginsSize, and setSize() (lines 608-610) which properly adjusts \_noPluginsSize on size changes. The \_removeSlot() internal function (lines 706-732) only handles linked-list cleanup and sets exists=false without touching \_noPluginsSize.
>
> State flow:
>
> 1. Subvault slot created with noPlugins=true, size=100. \_noPluginsSize += 100
> 2. Vault is slashed or emptied so getAllocated(subvaultIndex, 0)==0 despite size>0
> 3. Curator calls removeSlot(subvaultIndex) - succeeds because allocated==0
> 4. \_noPluginsSize still includes 100 from the removed slot
> 5. Vault receives new deposits. allocatable() = totalStake() - getNoPluginsSize() - pluginsAllocated is reduced by phantom 100

### Impact

> Permanent inflation of \_noPluginsSize reduces allocatable() in VaultV2 by the phantom amount. This limits plugin allocation capacity (plugins cannot allocate beyond the deflated allocatable value) and blocks creation of new noPlugins slots (the size check against allocatable fails). The inflation cannot be corrected because the removed slot is inaccessible (exists=false) to setSize or resetAllocation. For example, if phantom \_noPluginsSize is 100 ETH and totalStake is 150 ETH, allocatable returns 50 ETH instead of 150 ETH - a 67% reduction.

### Recommendation

> In removeSlot(), before calling \_removeSlot(index), check if the slot has noPlugins=true and decrement \_noPluginsSize by the slot's current size. For example:
>
> ```solidity
> if (index.getDepth() == 1 && slots[index].noPlugins) {
>     _noPluginsSize -= slots[index].size.latest();
> }
> ```
>
> Alternatively, enforce that setSize(index, 0) must be called before removeSlot for noPlugins slots.

---

## 12. [Medium] removeSlot on subvault slot orphans children with active network/operator mappings enabling phantom slashable stake

- IDs: 3
- Sources: FINDINGS2.json
- Affected: src/contracts/delegator/UniversalDelegator.sol:684,685,686,687,688,689,690,691,692,693,694,695,696,697,698,699,700,701,702,703

### Description

> When removeSlot() is called on a depth-1 (subvault) slot, it only clears the subvault's linked-list position and sets exists=false. It does NOT clear the state of child slots (depth-2 network slots and depth-3 operator slots). Critically, the \_networkToSlot and \_operatorToSlot mappings for children remain intact.
>
> State flow:
>
> 1. Subvault G created with network child N mapped to subnetwork X, operator child O mapped to operator addr
> 2. Vault empties (getAllocated(G, 0)==0 despite G.size>0)
> 3. Curator calls removeSlot(G) - G removed from root's linked list, G.exists=false
> 4. \_networkToSlot[X] still points to N, \_operatorToSlot[N][addr] still points to O
> 5. Vault receives new deposits, getBalance(0, 0) > 0
> 6. getSlotOf(X, addr) returns orphaned O. getAllocated(O, 0) computes through stale hierarchy:
>    - \_getPrevSum(G) returns stale value (possibly 0 if G was first child)
>    - getAllocated(G, 0) = min(rootAvailable - stalePrevSum, G.staleSize) > 0
>    - Cascades to non-zero allocation for N and O
> 7. slashableStake(X, addr, 0, '') returns phantom non-zero value
> 8. Middleware creates and executes slash request against phantom allocation
> 9. VaultV2.onSlash transfers real collateral to burner

### Impact

> Real vault collateral can be slashed based on phantom allocations from orphaned slots. The slashed amount is bounded by min(phantomAllocation, vaultBalance). Depositors who entered after the subvault removal lose funds to unnecessary slashing. In worst case (G was first child with prevSum=0 and large size), phantom allocation could equal the entire vault balance.

### Recommendation

> removeSlot() should recursively clean up all children when removing a subvault (depth-1) slot. For each child network slot, clear \_networkToSlot and \_slotToNetwork mappings. For each grandchild operator slot, clear \_operatorToSlot and \_slotToOperator mappings. Alternatively, add a check that prevents removing subvault slots that have existing children (existChildren > 0), forcing the curator to remove all children first via individual removeSlot calls.

---

## 13. [Informational] `SlotStorage.existChildren` counter may underflow on double-removal path

- IDs: fbeda87c-ca5f-4dad-a395-928189962454
- Sources: FINDINGS3.json
- Status: draft
- Accepted: true

### Description

> Lines:
>
> - [src/contracts/delegator/UniversalDelegator.sol#L744-L801](https://github.com/statemindio/audit-clones/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/delegator/UniversalDelegator.sol#L744-L801)
> - [src/contracts/delegator/UniversalDelegator.sol#L712-L739](https://github.com/statemindio/audit-clones/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/delegator/UniversalDelegator.sol#L712-L739)
>
> Description [`UniversalDelegator.resetAllocation()`](https://github.com/statemindio/audit-clones/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/delegator/UniversalDelegator.sol#L744-L801) may promote `index` to its parent and then call [`UniversalDelegator._removeSlot()`](https://github.com/statemindio/audit-clones/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/delegator/UniversalDelegator.sol#L712-L739) for a slot that may already be inactive. `_removeSlot()` runs in `unchecked` context and always decrements `parent.existChildren` (`--parent.existChildren`). If the parent counter is already `0`, the decrement underflows to `type(uint32).max` (`4294967295`), producing an impossible child count.
>
> Impact: Parent accounting may become structurally inconsistent (`existChildren` greatly above bounds), which may break list/counter assumptions used by invariants and may affect logic that depends on child cardinality.

### Recommendation

> We recommend preventing repeated removal on inactive slots and hardening the decrement path against underflow. A minimal guard can be applied before `_removeSlot()` and before decrement:
>
> ```diff
>  function resetAllocation(bytes32 subnetwork) public {
>      ...
> +    if (!slots[index].exists) {
> +        emit ResetAllocation(index, subnetwork);
> +        return;
> +    }
>      if (slots[index.getParentIndex()].existChildren == 1) {
>          index = index.getParentIndex();
>      }
>      ...
>      _removeSlot(index);
>  }
> ```
>
> ```diff
>  function _removeSlot(uint96 index) internal {
>      ...
> -    --parent.existChildren;
> +    if (parent.existChildren == 0) {
> +        revert InvalidChildrenCount();
> +    }
> +    --parent.existChildren;
>      slot.exists = false;
>      ...
>  }
> ```

---

## 14. [Informational] Capture timestamp boundary is inconsistent at the exact epoch edge

- IDs: 2421eb3a-0a3f-4347-bd55-44a933270d66
- Sources: FINDINGS3.json
- Status: draft
- Accepted: true
- Hidden: true

### Description

> Lines:
>
> - [UniversalSlasher.sol#L142-L147](https://github.com/symbioticfi/core-mirror/blob/cc21dbb9c30a216be4f8c818b4089595c4c1789b/src/contracts/slasher/UniversalSlasher.sol#L142-L147)
> - [UniversalSlasher.sol#L190](https://github.com/symbioticfi/core-mirror/blob/cc21dbb9c30a216be4f8c818b4089595c4c1789b/src/contracts/slasher/UniversalSlasher.sol#L190)
> - [UniversalSlasher.sol#L217](https://github.com/symbioticfi/core-mirror/blob/cc21dbb9c30a216be4f8c818b4089595c4c1789b/src/contracts/slasher/UniversalSlasher.sol#L217)
> - [UniversalDelegator.sol#L300-L304](https://github.com/symbioticfi/core-mirror/blob/cc21dbb9c30a216be4f8c818b4089595c4c1789b/src/contracts/delegator/UniversalDelegator.sol#L300-L304)
>
> `UniversalSlasher.slashableStake()` treats `captureTimestamp == block.timestamp - epochDuration` as valid because staleness is checked with a strict `<` comparison. In parallel, `UniversalDelegator.getPending()` computes the rolling window by subtracting `upperLookupRecent(fromTimestamp)`, which excludes events exactly at `fromTimestamp`. Because `UniversalSlasher.requestSlash()` stores `createdAt` and `UniversalSlasher.executeSlash()` reevaluates slashability using that stored timestamp, a slash executed exactly one epoch later may still pass the slasher's timestamp validity check while pending exposure from that same boundary timestamp is no longer counted by delegator accounting.
>
> This mismatch may reduce executable slash at the exact boundary and can cause edge-case liveness issues where a request that appears time-valid executes for less than expected or reverts with `InsufficientSlash` if the boundary transition removes the remaining slashable pending.

### Recommendation

> We recommend aligning boundary semantics between `UniversalSlasher.slashableStake()` and delegator pending-window accounting so both components treat the epoch edge consistently. One immediate option is to make the slasher staleness check inclusive at the boundary:
>
> ```diff
> - captureTimestamp < block.timestamp.saturatingSub(IVault(vault).epochDuration())
> + captureTimestamp <= block.timestamp.saturatingSub(IVault(vault).epochDuration())
> ```

---

## 15. [Informational] Claimers cannot determine which withdrawal index to claim, enabling griefing and breaking claim flow

- IDs: 6ddd4989-dc31-4b06-9ee6-8e7cca36ee81
- Sources: FINDINGS1.json
- Status: review
- Accepted: true

### Description

> **Line:** [`VaultV2.sol#L294`](https://github.com/symbioticfi/core-mirror/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/vault/VaultV2.sol#L294), [`VaultV2.sol#L314`](https://github.com/symbioticfi/core-mirror/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/vault/VaultV2.sol#L314)
>
> In VaultV2, each withdrawal is identified by a per-claimer **index** equal to the length of that claimer’s withdrawal list at creation time. The index is stored in `_withdrawalsOfLength[claimer]` and used in `_withdrawalSharesOf[index][claimer]` and `_withdrawalUnlockAfter[index][claimer]` inside `_withdraw()`. Unlike Vault (V1), where withdrawals are keyed by **epoch** and a claimer can derive which epoch to claim from time (e.g. claim for `currentEpoch() - 1`), in V2 the index is an opaque monotonic counter per account. The contract does not expose the newly assigned index to the caller or the claimer: `withdraw()` returns only `(burnedShares, mintedShares)` and `redeem()` returns only `(withdrawnAssets, mintedShares)`. The `Withdraw` event also omits the index. So after a user (or an integrator) calls `withdraw(claimer, amount)` or `redeem(claimer, shares)`, they have no on-chain way to know which index was assigned except by assuming it is `withdrawalsOfLength(claimer) - 1` at the time of the call. That assumption is fragile: anyone with a small amount of vault shares can call `withdraw(targetClaimer, dust)` or `redeem(targetClaimer, dust)` and burn their own shares to create a withdrawal **for** `targetClaimer`. Each such call increments `_withdrawalsOfLength[targetClaimer]` and allocates the next index to that dust withdrawal. A griefer can repeatedly create dust withdrawals for a victim, so the victim’s indices are mixed with the victim’s real withdrawal(s). The victim then cannot tell which index corresponds to their real withdrawal and must either try all indices (costly and incomplete without knowing the set) or rely on off-chain logs; the event does not include the index, so index discovery is not straightforward.
>
> **Impact:** Claimers and integrators cannot reliably know which index to pass to `claim()` or `claimBatch()`. This breaks UX and integration (e.g. frontends or keepers that need to claim after a delay). A griefer can force a claimer into a large index space filled with dust, increasing gas and complexity to claim and making it easier to leave funds unclaimed or to mis-claim. The design regression versus V1 (epoch-based, predictable claim targets) exacerbates the issue.

### Recommendation

> Consider returning the assigned withdrawal index from `withdraw()` and `redeem()` so the caller and claimer can store or display it. Optionally extend the `Withdraw` event with a `uint256 indexed index` (or a non-indexed `index` if many distinct indices are expected) so index can be recovered from logs. Consider documenting that anyone with vault shares can create withdrawals on behalf of any claimer and that griefing via dust withdrawals is possible; if acceptable, consider a minimum withdrawal size or a small fee to make dust creation uneconomic.

---

## 16. [Informational] Confusing naming for withdrawal count and withdraw/redeem return value

- IDs: 1d52cb8c-7890-4893-9590-02ce670c15c5
- Sources: FINDINGS1.json
- Status: review
- Accepted: true

### Description

> Line: [`VaultV2.sol#L159`](https://github.com/symbioticfi/core-mirror/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/vault/VaultV2.sol#L159), [`VaultV2.sol#L294`](https://github.com/symbioticfi/core-mirror/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/vault/VaultV2.sol#L294), [`VaultV2.sol#L314`](https://github.com/symbioticfi/core-mirror/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/vault/VaultV2.sol#L314)
>
> Two naming choices may mislead integrators and users.
>
> **1. `withdrawalsOfLength(address account)`** — The name suggests “how many withdrawals the account has,” but the return value is used as the **next withdrawal index** (e.g. in `_withdraw()` at L536). For migrated vaults it can return `__migrateEpoch + 2` for accounts with no post-migration withdrawals (legacy support), which is not the count of user-created withdrawals. Users may therefore believe they have more distinct withdrawals than they actually do, or misinterpret the value as a count instead of an upper bound for valid claim indices.
>
> **2. `mintedShares` in `withdraw()` and `redeem()`** — Both functions return `(..., mintedShares)`. In `deposit()`, `mintedShares` denotes newly minted **vault** (active) shares. In `withdraw()` and `redeem()`, the same name is used for the **withdrawal-queue** shares credited to the claimer (used later in `withdrawalsOf()` and `claim()`). Reusing “mintedShares” for a different concept (withdrawal shares vs vault shares) can cause confusion and wrong assumptions in callers or frontends that treat all “minted shares” as vault shares.
>
> **Impact:** Misreading `withdrawalsOfLength` can lead to wrong iteration ranges or wrong UX (e.g. showing “N withdrawals” when the user has fewer). Confusing withdrawal-queue shares with vault shares in return values can cause incorrect accounting or display in integrators and UIs.

### Recommendation

> Consider renaming `withdrawalsOfLength` to a name that reflects its role as the next withdrawal index or the number of withdrawal slots (e.g. `nextWithdrawalIndex(account)` or `withdrawalCount(account)` with NatSpec clarifying that after migration it may include legacy slots). Consider renaming the return value of `withdraw()` and `redeem()` from `mintedShares` to `mintedWithdrawalShares` (and updating the interface, events, and NatSpec) so it is clear these are shares in the withdrawal queue, not vault shares.

---

## 17. [Informational] Gas optimization

- IDs: 13eaaa43-d412-4788-855e-450c4712dbf2, b17731f4-a842-4909-b9f2-d9d36b8d08ab
- Sources: FINDINGS1.json, FINDINGS3.json
- Status: draft, review_fail
- Accepted: true

### Description

> Line: [src/contracts/vault/VaultV2.sol#L210](https://github.com/statemindio/audit-clones/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/vault/VaultV2.sol#L210)
>
> The branch condition is `if (migrateEpoch == 0 || index >= migrateEpoch)`. Because `index` is an unsigned integer, `index >= migrateEpoch` is already true when `migrateEpoch == 0`, so the explicit `migrateEpoch == 0` clause does not affect behavior and only adds an extra comparison.

### Recommendation

> We recommend simplifying the condition.
>
> ```diff
> - if (migrateEpoch == 0 || index >= migrateEpoch) {
> + if (index >= migrateEpoch) {
> ```

---

## 18. [Informational] Incorrect storage gap update in the `VaultV2Storage` contract

- IDs: f24f3539-8ec2-4f94-9479-19089293ca36
- Sources: FINDINGS1.json
- Status: review
- Accepted: true

### Description

> Line: [VaultV2Storage.sol#L169](https://github.com/symbioticfi/core-mirror/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/vault/VaultV2Storage.sol#L169)
>
> New variables were added to `VaultV2Storage` compared to the `VaultStorage` contract. 14 variables have been added, which occupy 13 slots. Due to this update, the gap should have been reduced by 13(number of new slots), but it was reduced by 12.
>
> `Vault.sol` storage layout:
> | Name | Type | Slot |
> |-----------------|-------------------------------------------------|------|
> | \_activeSharesOf | mapping(address => struct Checkpoints.Trace256) | 14 |
> | **gap | uint256[50] | 15 |
> | **gap | uint256[10] | 65 |
>
> `VaultV2.sol` storage layout:
> | Name | Type | Slot |
> |-----------------|-----------------------------|------|
> | pluginAllocated | mapping(address => uint256) | 27 |
> | **gap | uint256[38] | 28 |
> | **gap | uint256[10] | 66 |
>
> Due to this mistake, the `MigratableEntity` storage gap was shifted by one slot compared to the previous storage.

### Recommendation

> We recommend changing the number of elements in the `VaultV2Storage.__gap` variable:
>
> ```diff
> - uint256[38] internal __gap;
> + uint256[37] internal __gap;
> ```

---

## 19. [Informational] Missing custom error for non-existent plugins in `VaultV2.swapPlugins()`

- IDs: 122379f3-e14b-4c63-b18f-c0c980ed952d
- Sources: FINDINGS1.json
- Status: review
- Accepted: true

### Description

> Lines: [VaultV2.sol#L618-L634](https://github.com/symbioticfi/core-mirror/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/vault/VaultV2.sol#L618)
>
> The `VaultV2.swapPlugins()` function will revert without a custom error if a plugin address is not found in the plugins array.
>
> For better debuggability and off-chain error handling, it is better to revert a custom error.

### Recommendation

> We recommend adding a custom error `PluginNotFound()` and checking whether plugins were found or not.

---

## 20. [Informational] Redundant `VaultV2.deallocatePlugins()` calls in `claimBatch()` function

- IDs: d2c2c628-befd-4106-9a6c-afe376a31db7
- Sources: FINDINGS1.json
- Status: review
- Accepted: true

### Description

> Lines:
>
> - [VaultV2.sol#L371](https://github.com/symbioticfi/core-mirror/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/vault/VaultV2.sol#L371)
> - [VaultV2.sol#L401](https://github.com/symbioticfi/core-mirror/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/vault/VaultV2.sol#L401)
>
> The `VaultV2.claimBatch()` function iterates over `indexes` and calls `VaultV2.claim()` for each index. Each call to `VaultV2.claim()` triggers the `VaultV2.withDeallocatePlugins(true)` modifier, which in turn calls `deallocatePlugins()`.
>
> It is redundant to call `VaultV2.deallocatePlugins()` function for each index.

### Recommendation

> We recommend extracting the core claim logic into `VaultV2._claim()` function without the `VaultV2.withDeallocatePlugins()` modifier and apply this modifier to `VaultV2.claimBatch()` function.
>
> ```solidity
> function claimBatch(address recipient, uint256[] calldata indexes)
>     public
>     withDeallocatePlugins(true)
>     nonReentrant
>     returns (uint256 amount)
> {
>     unchecked {
>         for (uint256 i; i < indexes.length; ++i) {
>             amount += _claim(recipient, indexes[i]);
>         }
>     }
> }
>
> function claim(address recipient, uint256 index)
>     public
>     withDeallocatePlugins(true)
>     nonReentrant
>     returns (uint256 amount)
> {
>     return _claim(recipient, index);
> }
> ```

---

## 21. [Informational] Removed child may remain linked in parent child list

- IDs: 93a4efe6-11c0-4204-95e5-5be86415075b
- Sources: FINDINGS3.json
- Status: draft
- Accepted: true

### Description

> Lines:
>
> - [src/contracts/delegator/UniversalDelegator.sol#L690-L739](https://github.com/statemindio/audit-clones/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/delegator/UniversalDelegator.sol#L690-L739)
> - [src/contracts/delegator/UniversalDelegator.sol#L744-L801](https://github.com/statemindio/audit-clones/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/delegator/UniversalDelegator.sol#L744-L801)
>
> Description [`UniversalDelegator.removeSlot()`](https://github.com/statemindio/audit-clones/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/delegator/UniversalDelegator.sol#L690-L709) and [`UniversalDelegator.resetAllocation()`](https://github.com/statemindio/audit-clones/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/delegator/UniversalDelegator.sol#L744-L801) both route through [`UniversalDelegator._removeSlot()`](https://github.com/statemindio/audit-clones/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/delegator/UniversalDelegator.sol#L712-L739), which rewrites linked-list pointers and then sets `slot.exists = false`. Under specific interleavings, a removed child may still be reachable from the parent chain (`firstChild` or sibling `nextSlot`). In replayed invariant traces, root traversal reached a removed child slot and failed `assertTrue(childSlot.exists)`, showing that parent pointers can reference deleted nodes.
>
> Impact: Parent-child topology may become inconsistent because traversal can hit inactive slots that should no longer be in the linked list. Any accounting or safety checks that assume reachable children are active may compute on stale structure and may diverge from expected tree state.

### Recommendation

> We recommend hardening removal flows so parent links cannot reference inactive children after any remove/reset sequence. A minimal mitigation is to reject internal removal of already inactive slots and canonicalize parent pointers when a parent becomes empty.
>
> ```diff
>  function _removeSlot(uint96 index) internal {
>      SlotStorage storage slot = slots[index];
>      SlotStorage storage parent = slots[index.getParentIndex()];
> +    if (!slot.exists) {
> +        revert SlotNotExists();
> +    }
>      ...
>      --parent.existChildren;
> +    if (parent.existChildren == 0) {
> +        parent.firstChild.push(uint48(block.timestamp), 0);
> +        parent.lastChild.push(uint48(block.timestamp), 0);
> +    }
>      slot.exists = false;
>      ...
>  }
> ```
>
> We also recommend validating linked neighbors used during pointer rewrites, and recomputing nearest active neighbors before writing `firstChild`, `lastChild`, or sibling `nextSlot` links.

---

## 22. [Informational] Reset allocation may emit a parent index instead of the subnetwork slot index

- IDs: cfea6f12-d167-47df-8f7a-5251da467bff
- Sources: FINDINGS3.json
- Status: draft
- Accepted: true
- Hidden: true

### Description

> Lines:
>
> - [UniversalDelegator.sol#L769-L771](https://github.com/symbioticfi/core-mirror/blob/cc21dbb9c30a216be4f8c818b4089595c4c1789b/src/contracts/delegator/UniversalDelegator.sol#L769-L771)
> - [UniversalDelegator.sol#L807](https://github.com/symbioticfi/core-mirror/blob/cc21dbb9c30a216be4f8c818b4089595c4c1789b/src/contracts/delegator/UniversalDelegator.sol#L807)
> - [IUniversalDelegator.sol#L233-L237](https://github.com/symbioticfi/core-mirror/blob/cc21dbb9c30a216be4f8c818b4089595c4c1789b/src/interfaces/delegator/IUniversalDelegator.sol#L233-L237)
>
> `UniversalDelegator.resetAllocation()` first resolves the slot assigned to the provided `subnetwork`, but conditionally replaces `index` with `index.getParentIndex()` when the parent has a single child. The same `index` value is then emitted in `ResetAllocation(index, subnetwork)`. As a result, the emitted `index` may represent the collapsed parent subvault, while the event documentation describes it as the slot index that was reset for the subnetwork.

### Recommendation

> We recommend emitting the original subnetwork slot index separately from the actually removed index when parent collapse occurs, so event semantics remain explicit and stable for integrators. One practical option is to preserve the original slot in a local variable and include both values in the event (or add a dedicated event for collapsed-parent resets).

---

## 23. [Informational] Shared `setSize` can reduce or cancel an already requested slash

- IDs: 058daf91-68a6-4b2f-af09-0424f9d5e10f
- Sources: FINDINGS3.json
- Status: draft
- Accepted: true

### Description

> `UniversalDelegator.setSize()` only creates pending protection on size decreases when `!parent.isShared`. For slots under a shared parent, decreasing `size` updates slashable allocation immediately because no pending is added. In parallel, `UniversalSlasher.slashableStake()` (post-migration path) returns current `stakeFor(...)` even when `executeSlash()` passes `request.createdAt`, and `executeSlash()` computes `min(request.amount, currentSlashable)`. This means a slash that was valid and requested at time `T` can be reduced or fully canceled if a curator decreases shared-slot size before execution.
>
> Impact: Requested slashes are not stable during the veto/execution delay for shared-parent allocations. A network can submit a valid request, but execution may settle for a smaller amount (or revert with `InsufficientSlash`) solely due to an intermediate shared `setSize` decrease, weakening predictability of slash enforcement.

### Recommendation

> We recommend aligning slash execution semantics with request-time exposure for shared-parent slots. One option is to snapshot slashable exposure at request time (or enforce an equivalent reservation) and cap execution against that snapshot. Another option is to introduce pending protection for shared-parent decreases so stake remains slashable for the full slash window.

---

## 24. [Informational] Unused \_cumulativeSlash storage variable in UniversalDelegator

- IDs: 31e6acf1-9099-4683-b8ec-b6016a2a38ca
- Sources: FINDINGS1.json, FINDINGS3.json
- Status: draft
- Accepted: true
- Hidden: true

### Description

> Line: [UniversalDelegator.sol#L105](https://github.com/symbioticfi/core-mirror/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/delegator/UniversalDelegator.sol#L105)
>
> The `_cumulativeSlash` mapping is declared in `UniversalDelegator` but is never read or written by any function in the contract:
>
> ```solidity
> /// @dev Cumulative slashed amounts per slot.
> mapping(uint96 index => Checkpoints.Trace208 amount) internal _cumulativeSlash;
> ```
>
> The `onSlash()` function handles slash accounting by adjusting `size`, `pendingCumulative`, `clearedPendingCumulative`, `clearedChildrenPendingCumulative`, and `_clearedNoPluginsPendingCumulative`, but never updates `_cumulativeSlash`. Similarly, no view function reads from it.

### Recommendation

> Consider removing the `_cumulativeSlash` mapping from `UniversalDelegator`.

---

## 25. [Informational] Unused \_rootSlot function in UniversalDelegator

- IDs: 4f939c9d-9d03-4096-a01c-221371a40779
- Sources: FINDINGS1.json, FINDINGS3.json
- Status: draft
- Accepted: true
- Hidden: true

### Description

> Line: [UniversalDelegator.sol#L993](https://github.com/symbioticfi/core-mirror/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/delegator/UniversalDelegator.sol#L993)
>
> The `_rootSlot()` helper function is declared but never called anywhere in the contract:
>
> ```solidity
> /// @dev Return storage pointer to the root slot.
> function _rootSlot() internal view returns (SlotStorage storage) {
>     return slots[0];
> }
> ```
>
> `_rootSlot()` has no callers. All access to the root slot throughout the contract is done directly via `slots[0]` or through the general `slots[index]` pattern.

### Recommendation

> Consider removing the `_rootSlot()` function.

---

## 26. [Informational] VaultV2 ERC20 transfer bypasses deposit whitelist allowing non-whitelisted accounts to hold vault shares

- IDs: c45f9d9d-ff77-4873-8f2e-9be67e0748ff
- Sources: FINDINGS1.json
- Status: review
- Accepted: true

### Description

> Line: [`VaultV2.sol#L800`](https://github.com/symbioticfi/core-mirror/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/vault/VaultV2.sol#L800)
>
> The vault implements `depositWhitelist` to restrict who can deposit, but ERC20 `transfer` and `transferFrom` (inherited from ERC20Upgradeable) have no restrictions. A whitelisted depositor can transfer shares to any address, effectively circumventing the whitelist. The non-whitelisted recipient can then withdraw or redeem these shares.
>
> ```solidity
> function _update(address from, address to, uint256 value) internal override {
>     _activeSharesOf[from].push(uint48(block.timestamp), balanceOf(from) - value);
>     unchecked {
>         _activeSharesOf[to].push(uint48(block.timestamp), balanceOf(to) + value);
>     }
>     emit Transfer(from, to, value);
> }
> ```
>
> No whitelist check in transfer path.
>
> Impact: The deposit whitelist can be completely bypassed through secondary market transfers. Non-whitelisted addresses can acquire vault shares and participate in withdrawals, redemptions, and instant withdrawals. This undermines any compliance or access control requirements the vault curator intended to enforce through the whitelist.

### Recommendation

> We recommend to override `transfer` and `transferFrom` to enforce whitelist checks on the recipient, or document that the whitelist only controls the deposit entry point and not share ownership.

---

## 27. [Informational] VaultV2 interface contains unused errors and omits declared `IVaultV2.ClaimBatch` emission

- IDs: cc6ec829-fce1-4120-a5e9-2d7edfbd1952
- Sources: FINDINGS1.json
- Status: review_fail
- Accepted: true

### Description

> Lines:
>
> - [src/interfaces/vault/IVaultV2.sol#L60](https://github.com/symbioticfi/core-mirror/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/interfaces/vault/IVaultV2.sol#L60)
> - [src/interfaces/vault/IVaultV2.sol#L65](https://github.com/symbioticfi/core-mirror/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/interfaces/vault/IVaultV2.sol#L65)
> - [src/interfaces/vault/IVaultV2.sol#L308](https://github.com/symbioticfi/core-mirror/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/interfaces/vault/IVaultV2.sol#L308)
>
> `IVaultV2` declares `DuplicateDepositor` and `DuplicatePlugin`, but there is no revert path in `VaultV2` that uses either selector. `IVaultV2` also declares `ClaimBatch`, but `VaultV2.claimBatch()` does not emit `ClaimBatch` after summing the amount.

### Recommendation

> We recommend aligning interface declarations with implementation behavior.
>
> `VaultV2.sol`:
>
> ```solidity
> function claimBatch(address recipient, uint256[] calldata indexes) public returns (uint256 amount) {
>     unchecked {
>         for (uint256 i; i < indexes.length; ++i) {
>             amount += claim(recipient, indexes[i]);
>         }
>     }
>     emit ClaimBatch(msg.sender, recipient, indexes, amount);
> }
> ```
>
> `IVaultV2.sol`:
>
> ```diff
> -error DuplicateDepositor();
> -error DuplicatePlugin();
> ```

---

## 28. [Informational] VaultV2 slashing can be blocked by plugin deallocation revert

- IDs: b4822636-1ba4-4d03-b77b-86efb5b79e57
- Sources: FINDINGS1.json
- Status: review_fail
- Accepted: true

### Description

> Lines:
>
> - [src/contracts/vault/VaultV2.sol#L435](https://github.com/statemindio/audit-clones/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/vault/VaultV2.sol#L435)
>
> `VaultV2.onSlash()` executes through `withDeallocatePlugins(withPlugins)`, which calls `deallocatePlugins()` before slashing logic. In `deallocatePlugins()`, each plugin can be called via `IPluginBase(plugin).deallocate(...)`, followed by `collateral.safeTransferFrom(...)`, and any revert bubbles up because there is no isolation or fallback handling. `UniversalSlasher.executeSlash()` can pass `withPlugins = true` for plugin-enabled subnetworks, so slash execution enters this pre-deallocation path. As a result, when a plugin deallocation path reverts, slash execution may revert.

### Recommendation

> We recommend decoupling slash finalization from plugin deallocation success.

---

## 29. [Informational] VaultV2 trusts plugin deallocate return value and can underflow accounting

- IDs: 4c4f2c46-57ef-4f25-b13a-9db07bf87216
- Sources: FINDINGS1.json
- Status: review_fail
- Accepted: true

### Description

> Lines:
>
> - [src/contracts/vault/VaultV2.sol#L684](https://github.com/statemindio/audit-clones/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/vault/VaultV2.sol#L684)
>
> `VaultV2._deallocatePlugin()` trusts `IPluginBase(plugin).deallocate(amount)` and subtracts the returned value directly from `pluginAllocated[plugin]`. If a plugin returns more than currently allocated `deallocated`, `pluginAllocated[plugin] -= deallocated` reverts with arithmetic underflow.

### Recommendation

> We recommend validating or capping plugin-reported deallocation before accounting updates so vault-side bookkeeping cannot underflow on plugin-provided return data.
>
> ```diff
> - deallocated = IPluginBase(plugin).deallocate(amount);
> + uint256 reported = IPluginBase(plugin).deallocate(amount);
> + uint256 allocated = pluginAllocated[plugin];
> + deallocated = Math.min(reported, Math.min(amount, allocated));
>   if (deallocated > 0) {
>       collateral.safeTransferFrom(plugin, address(this), deallocated);
> -
> -     pluginAllocated[plugin] -= deallocated;
> +     pluginAllocated[plugin] = allocated - deallocated;
>       unchecked {
>           pluginsAllocated -= deallocated;
>       }
>   }
> ```

---

## 30. [Informational] VaultV2.donate distributes rewards proportionally but can be gamed via sandwich attack

- IDs: cad55c1d-ffe3-4730-b215-dadb308da30a
- Sources: FINDINGS1.json
- Status: review
- Accepted: true

### Description

> Line: [`VaultV2.sol#L407`](https://github.com/symbioticfi/core-mirror/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/vault/VaultV2.sol#L407)
>
> The `donate` function distributes donated amounts proportionally between `activeStake` and `activeWithdrawals`. An attacker can sandwich a large donation by: (1) Depositing a large amount just before the donation (increasing their share of activeStake), (2) Letting the donation execute (their deposit captures a disproportionate share), (3) Initiating a withdrawal immediately after.
>
> The key insight is that `deposit` is permissionless (or requires only whitelisting) and the donation amount is public in the mempool:
>
> ```solidity
> uint256 withdrawalsDonated = amount.fullMulDiv(curActiveWithdrawals, curActiveStake + curActiveWithdrawals);
> _activeStake.push(uint48(block.timestamp), amount - withdrawalsDonated + curActiveStake);
> ```
>
> Impact: An attacker can extract a significant portion of donated rewards by front-running the `donate` transaction with a large deposit, then withdrawing after the donation. The cost is limited to the withdrawal epoch lock period (opportunity cost) but for large donations, the extracted value could be substantial.

### Recommendation

> Consider implementing a deposit cooldown or time-weighted share calculation for rewards distribution. Alternatively, use a drip mechanism that distributes rewards over multiple blocks rather than all at once.

---

## 31. [Informational] Wrong parameter in InstantWithdraw event emission

- IDs: 467d26e0-329b-406d-91d7-0b12cdc39714
- Sources: FINDINGS1.json
- Status: review
- Accepted: true

### Description

> Line: [VaultV2.sol#L363](https://github.com/symbioticfi/core-mirror/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/vault/VaultV2.sol#L363)
>
> The [`instantWithdraw()`](https://github.com/symbioticfi/core-mirror/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/vault/VaultV2.sol#L334) function accepts a `recipient` parameter and transfers collateral to that address. However, the `InstantWithdraw` event logs `msg.sender` as the first argument instead of `recipient`:
>
> ```solidity
> collateral.safeTransfer(recipient, withdrawnAssets);
>
> emit InstantWithdraw(msg.sender, withdrawnAssets, burnedShares);
> ```
>
> The [`InstantWithdraw`](https://github.com/symbioticfi/core-mirror/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/interfaces/vault/IVaultV2.sol#L290) event definition documents its first parameter as the account that received the collateral. When a caller specifies a `recipient` different from `msg.sender`, the event records an incorrect address, as the collateral is sent to `recipient` while the event attributes it to `msg.sender`.

### Recommendation

> We recommend passing `recipient` instead of `msg.sender` to the `InstantWithdraw` event to match the actual transfer destination. Additionally, consider adding a `withdrawer` parameter to align with the pattern used by other vault events such as `Deposit`, `Withdraw`, and `Claim`, which all emit both the caller and the beneficiary:
>
> ```diff
> - event InstantWithdraw(address indexed recipient, uint256 amount, uint256 burnedShares);
> + event InstantWithdraw(address indexed withdrawer, address indexed recipient, uint256 amount, uint256 burnedShares);
> ```
>
> ```diff
> - emit InstantWithdraw(msg.sender, withdrawnAssets, burnedShares);
> + emit InstantWithdraw(msg.sender, recipient, withdrawnAssets, burnedShares);
> ```

---

## 32. [Informational] `resetAllocation` does not check if collapsed parent subvault exists

- IDs: 56c0ccd5-ec01-4d98-bde6-9d76732a1639
- Sources: FINDINGS3.json
- Status: draft
- Accepted: true

### Description

> Line: [UniversalDelegator.sol#L758](https://github.com/symbioticfi/core-mirror/blob/53b68070799a9d456856cde00723b4cc0d0bc80e/src/contracts/delegator/UniversalDelegator.sol#L758)
>
> When `resetAllocation()` is called on a network that is the sole remaining child of a subvault, it collapses the operation to the parent subvault and removes it. However, the code does not verify that the parent subvault actually exists before collapsing:
>
> ```solidity
> if (slots[index.getParentIndex()].existChildren == 1) {
>     index = index.getParentIndex();
> }
> ```
>
> If the parent subvault was already removed (via `removeSlot()` or a prior `resetAllocation()`), its `existChildren` field may still be 1 — `_removeSlot()` only decrements the _parent's_ `existChildren`, not the removed slot's own `existChildren`. Meanwhile, the network's `_networkToSlot` mapping is not cleared when its parent subvault is removed (since `removeSlot` only clears mappings for the slot being removed, and subvaults do not carry network mappings). This allows a subsequent `resetAllocation()` to find the orphaned network, collapse to the already-removed subvault, and call `_removeSlot()` on it a second time.
>
> ## Corruption details
>
> When `_removeSlot()` executes on an already-removed subvault, it operates on stale linked-list pointers in an `unchecked` block, causing three distinct corruptions:
>
> **1. `root.existChildren` underflow.** If root has no existing subvaults (or fewer than expected), the decrement wraps:
>
> ```solidity
> --parent.existChildren; // 0 → 0xFFFFFFFF in unchecked
> ```
>
> This breaks the `MAX_SUBVAULTS` check in `_createSlot()`. With `existChildren = 0xFFFFFFFF`, the next `++parent.existChildren` overflows to 0, bypassing the limit. The counter becomes permanently misaligned from the actual number of subvaults, and can underflow again on subsequent removals.
>
> **2. Root slot's `nextSlot` overwritten.** The removed subvault's `childIndex` no longer matches `root.firstChild` (which was set to 0 or another subvault during the original removal). The else branch executes:
>
> ```solidity
> slots[index.getParentIndex().createIndex(slot.prevSlot)].nextSlot
>     .push(uint48(block.timestamp), uint32(slot.nextSlot.latest()));
> ```
>
> For the first subvault under root, `prevSlot = 0`. Since `createIndex(0, 0) = 0`, this writes to `slots[0].nextSlot` — the root slot itself — setting it to `WITHDRAWAL_BUFFER_CHILD_INDEX`.
>
> **3. Withdrawal buffer's `prevSlot` overwritten.** Similarly, the subvault's `childIndex` won't match `root.lastChild`, so the else branch executes:
>
> ```solidity
> slots[index.getParentIndex().createIndex(uint32(slot.nextSlot.latest()))].prevSlot = slot.prevSlot;
> ```
>
> The subvault's stale `nextSlot` is `WITHDRAWAL_BUFFER_CHILD_INDEX`, so `createIndex(0, 0xFFFFFFFF) = WITHDRAWAL_BUFFER_INDEX`. The withdrawal buffer slot's `prevSlot` is overwritten with the subvault's stale `prevSlot` value.
>
> ## Example scenario
>
> 1. Curator creates subvault G1 (childIndex=1, size=100) with a single network N1.
> 2. Curator calls `setSize(G1, 0)` then `removeSlot(G1)`. G1 is removed from root's linked list (`root.firstChild = 0`, `root.lastChild = 0`, `root.existChildren = 0`, `G1.exists = false`). N1's `_networkToSlot` mapping is **not** cleared because `removeSlot` only clears mappings on the removed slot itself, and G1 is a subvault with no network mapping.
> 3. N1's network (or middleware) calls `resetAllocation(subnetwork)`.
> 4. `getSlotOfNetwork(subnetwork)` returns N1's index (still mapped), passing the `index == 0` check.
> 5. `slots[N1.getParentIndex()].existChildren` reads `G1.existChildren = 1` (unchanged from G1's original creation). The condition is true, so the code collapses: `index = G1`.
> 6. `_removeSlot(G1)` executes a second time on the already-removed slot:
>    - `slots[0].nextSlot` overwritten with `WITHDRAWAL_BUFFER_CHILD_INDEX`
>    - `slots[WITHDRAWAL_BUFFER_INDEX].prevSlot` overwritten with 0
>    - `root.existChildren`: `0 - 1 = 0xFFFFFFFF` (underflow)
>
> No vault depletion or adversarial conditions are required — a curator performing routine subvault cleanup followed by any external network calling `resetAllocation` is sufficient.

### Recommendation

> We recommend adding an existence check before collapsing to the parent subvault:
>
> ```diff
> - if (slots[index.getParentIndex()].existChildren == 1) {
> + if (slots[index.getParentIndex()].exists && slots[index.getParentIndex()].existChildren == 1) {
>       index = index.getParentIndex();
>   }
> ```
>
> Additionally, consider having `removeSlot` clear the network and operator mappings of child slots when removing a subvault or network that still has children, to prevent orphaned slots from being reachable via `getSlotOfNetwork` / `getSlotOfOperator`.

---

## 33. [Informational] `swapSlots` can reorder orphaned slots under a removed parent

- IDs: e0a987cb-c6ec-4f42-a959-06b7c417687e
- Sources: FINDINGS3.json
- Status: draft
- Accepted: true
- Hidden: true

### Description

> Lines:
>
> - [UniversalDelegator.sol#L118-L121](https://github.com/symbioticfi/core-mirror/blob/cc21dbb9c30a216be4f8c818b4089595c4c1789b/src/contracts/delegator/UniversalDelegator.sol#L118-L121)
> - [UniversalDelegator.sol#L625-L643](https://github.com/symbioticfi/core-mirror/blob/cc21dbb9c30a216be4f8c818b4089595c4c1789b/src/contracts/delegator/UniversalDelegator.sol#L625-L643)
> - [UniversalDelegator.sol#L692-L710](https://github.com/symbioticfi/core-mirror/blob/cc21dbb9c30a216be4f8c818b4089595c4c1789b/src/contracts/delegator/UniversalDelegator.sol#L692-L710)
> - [UniversalDelegator.sol#L736-L737](https://github.com/symbioticfi/core-mirror/blob/cc21dbb9c30a216be4f8c818b4089595c4c1789b/src/contracts/delegator/UniversalDelegator.sol#L736-L737)
>
> `UniversalDelegator.swapSlots()` validates only that `index1` and `index2` individually exist via `slotExists(index)`, but it does not verify that their parent slot still exists or that both indices are still part of an active subtree. In parallel, `UniversalDelegator.removeSlot()` can remove a parent slot without requiring `existChildren == 0`, and `_removeSlot()` marks only the removed slot as `exists = false`. This allows descendants to remain `exists = true` after their ancestor is removed. As a result, a curator can call `swapSlots()` on these detached descendants and mutate ordering/pointers inside an orphaned subtree.

### Recommendation

> We recommend enforcing parent-liveness and active-membership invariants in `UniversalDelegator.swapSlots()`, and preventing orphan creation in `UniversalDelegator.removeSlot()`. A practical approach is to require `slots[parentIndex].exists` during swaps and to require `slots[index].existChildren == 0` before allowing removal, or otherwise perform recursive cleanup that clears/removes descendants before parent removal.
