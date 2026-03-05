## 1. Network can nullify pending slash requests via resetAllocation
- Invalid. Network is the one who slashes, so there is no misalignment. The only thing to think of is scenario: Network resets alloc, Curator set alloc again sooner than epoch after, the old requests are executable (but then network middleware should not execute such "legacy" request in theory).

## 2. Withdrawal requests can be repriced at the unlock boundary during slashing
- Invalid for the current state. Currently invalid description as the slashing window is the whole `epoch`, not `epoch - 1`. But at the end we will make the slashing window equal to `epoch - 1`, as this simplifies the Vault's logic (while in theory breaks legacy guarantees for this single second).

## 3. If an operator in a shared subvault is slashed, every operator in the subvault is affected
- Valid. Potential fix is using "clear" vars of subvault and networks to calculate other networks' balance.

## 4. Non-Zero size persists after slot removal
- Invalid. Do not care about `getAllocated(slotIndex)`, only about `stake...(subnet, op)` which will return 0 (`getAllocated(subnet, op)` will return 0 too).

## 5. Pending calculation underreports when a clearing event outlives its corresponding pending in the time window
- Can be valid, but need to verify deeply (underreport seems not so bad as overreport).

## 6. Stale `prevSum` in withdrawal buffer after last subvault removal
- Valid.

## 7. UniversalDelegator createSlot does not validate subnetwork against network registry
- Acknowledged (registration is just permissionless call of single function, so even registered network can not be able to slash).

## 8. User funds are not slashable and not claimable when `block.timestamp == unlockAfter`
- Duplicate with (2).

## 9. `removeSlot` does not zero slot size on removal
- Valid. Will clear subvaults' children network-to-slot values.

## 10. `resetAllocation` does not clean up child operator slot state when removing entire subvault (existChildren == 1)
- Acknowledged / Invalid.

## 11. removeSlot does not decrement \_noPluginsSize for noPlugins subvault slots
- Valid, but need to add comment that it's possible only when the slot was not allocated for the whole epoch while has size.

## 12. removeSlot on subvault slot orphans children with active network/operator mappings enabling phantom slashable stake
- Duplicate with (9).

## 13. `SlotStorage.existChildren` counter may underflow on double-removal path
- Acknowledged. Such scenario seems impossible for adequate cases.

## 14. Capture timestamp boundary is inconsistent at the exact epoch edge
- Valid. Related to (2).

## 15. Claimers cannot determine which withdrawal index to claim, enabling griefing and breaking claim flow
- Acknowledged. We shouldn't break the legacy return decoding.

## 16. Confusing naming for withdrawal count and withdraw/redeem return value
- Acknowledged.

## 17. Gas optimization
- Valid.

## 18. Incorrect storage gap update in the `VaultV2Storage` contract
- Invalid.

## 19. Missing custom error for non-existent plugins in `VaultV2.swapPlugins()`
- Acknowledged.

## 20. Redundant `VaultV2.deallocatePlugins()` calls in `claimBatch()` function
- Acknowledged. `claimBatch()` should not be used now as VaultV2 is multicallable.

## 21. Removed child may remain linked in parent child list
- Invalid.

## 22. Reset allocation may emit a parent index instead of the subnetwork slot index
- Acknowledged.

## 23. Shared `setSize` can reduce or cancel an already requested slash
- Valid (think should be upper severity).

## 24. Unused \_cumulativeSlash storage variable in UniversalDelegator
- Valid.

## 25. Unused \_rootSlot function in UniversalDelegator
- Valid.

## 26. VaultV2 ERC20 transfer bypasses deposit whitelist allowing non-whitelisted accounts to hold vault shares
- Acknowledged (It's also possible do same on deposit).

## 27. VaultV2 interface contains unused errors and omits declared `IVaultV2.ClaimBatch` emission
- Valid.

## 28. VaultV2 slashing can be blocked by plugin deallocation revert
- Acknowledged.

## 29. VaultV2 trusts plugin deallocate return value and can underflow accounting
- Acknowledged.

## 30. VaultV2.donate distributes rewards proportionally but can be gamed via sandwich attack
- Acknowledged.

## 31. Wrong parameter in InstantWithdraw event emission
- Valid, but will just change recipient to withdrawer in event definition.

## 32. `resetAllocation` does not check if collapsed parent subvault exists
- Acknowledged.

## 33. `swapSlots` can reorder orphaned slots under a removed parent
- Acknowledged.

