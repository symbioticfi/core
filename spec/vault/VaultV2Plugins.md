# Vault V2 Plugins

This document specifies Vault V2 plugin functionality as implemented in:
`src/contracts/vault/VaultV2.sol`, `src/contracts/vault/VaultV2Storage.sol`, and related interfaces.

## Overview

Plugins allow Vault V2 to temporarily externalize collateral while tracking the amount owed back to the vault.
The vault maintains per-plugin and global debt accounting and can request repayment via a best-effort callback.

## Components

- `VaultV2`: owns plugin state and exposes plugin-facing functions.
- `PluginRegistry`: whitelists plugin addresses (owner-managed).
- `IBasePlugin`: minimal plugin interface used by the vault.

### Plugin interface

`IBasePlugin` exposes a single callback:

- `triggerPush(uint256 amount) external returns (bool)`

The plugin should transfer `amount` of collateral back to the vault and return `true` on success.

## Roles and gating

- `ADD_PLUGIN_ROLE` and `REMOVE_PLUGIN_ROLE` gate plugin lifecycle changes.
- `addPlugin` requires `IRegistry(PLUGIN_REGISTRY).isEntity(plugin)` to be true.
- `removePlugin` does not consult the registry (unwhitelisting does not auto-remove).
- Plugin roles are not granted in `InitParams`; they must be granted post-deploy by an admin.

## State

VaultV2 tracks:

- `pluginActiveSince[plugin]` (`uint48`): activation timestamp (also used as a membership flag).
- `plugins[]`: array of active plugin addresses (order affects repayment priority).
- `pluginsOwe` (`uint256`): total collateral owed across all plugins.
- `pluginOwe[plugin]` (`uint256`): collateral owed by a specific plugin.

## Lifecycle

1. **Whitelist** the plugin in `PluginRegistry` (owner-only).
2. **Add** via `addPlugin(plugin)` (requires `ADD_PLUGIN_ROLE`).
   - Appends to `plugins[]`.
   - Sets `pluginActiveSince[plugin] = uint48(block.timestamp)`.
3. **Operate** via `pull`/`push` and vault-triggered `triggerPush`.
4. **Remove** via `removePlugin(plugin)` (requires `REMOVE_PLUGIN_ROLE`).
   - Only allowed when `pluginOwe[plugin] == 0`.
   - Removes from `plugins[]` via swap-with-last.
   - Resets `pluginActiveSince[plugin] = 0`.

## External liquidity flows

### `pull(uint256 amount) -> uint256 pulled`

Purpose: allow a plugin to pull collateral out of the vault while recording debt.

Checks and behavior:

- Reverts with `InsufficientAmount` if `amount == 0`.
- Reverts with `PluginNotActive` if `pluginActiveSince[msg.sender] < block.timestamp`.
- `pulled = min(amount, activeStake().saturatingSub(pluginsOwe))`.
- Transfers `pulled` to `msg.sender`.
- Verifies plugin balance increased by `pulled`; otherwise reverts `FeeOnTransferNotSupported`.
- Updates accounting:
  - `pluginsOwe += pulled`
  - `pluginOwe[msg.sender] += pulled`
- Emits `Pull(plugin, pulled)`.

Notes:

- `pulled` can be zero if `pluginsOwe >= activeStake()`; this does not revert.
- `pull` does not check registry or array membership; the active check is only via `pluginActiveSince`.

### `push(uint256 amount)`

Purpose: allow a plugin to return collateral to the vault and reduce its debt.

Checks and behavior:

- Reverts with `InsufficientAmount` if `amount == 0`.
- Transfers `amount` from `msg.sender` to the vault (requires approval).
- Updates accounting:
  - `pluginsOwe -= amount`
  - `pluginOwe[msg.sender] -= amount`
- Emits `Push(plugin, amount)`.

Notes:

- `push` does not validate received amount; fee-on-transfer collateral can desync accounting.
- Underflow (amount > owed) reverts via Solidity arithmetic checks (no explicit custom error).

## Repayment via `_pullPlugins`

`_pullPlugins()` attempts to recover owed collateral from plugins. It is best-effort.

Behavior:

- `amount = activeStake().saturatingSub(pluginsOwe)`
- Iterates `plugins[]` in order.
- For each plugin with `pluginOwe[plugin] > 0`:
  - `pullAmount = min(pluginOwe[plugin], amount)`
  - `success = IBasePlugin(plugin).triggerPush(pullAmount)`
  - If `success`:
    - `pluginOwe[plugin] -= pullAmount`
    - `pluginsOwe -= pullAmount`
    - `amount -= pullAmount`
  - Stops early if `amount == 0`.

Notes:

- The vault does not verify that collateral was actually transferred on `success`.
- Repayment priority follows `plugins[]` order (which can change on removals).

## Interaction points

`_pullPlugins()` is invoked to attempt repayment before or during critical flows:

- `onSlash`: called after slash accounting to reduce outstanding plugin debt before computing `owed`.
- `_withdraw`: called after updating stake/share checkpoints to reduce plugin debt.
- `_claim`: called before claim validation to reduce plugin debt.
- `syncOwedSlash`: called before computing owed slash to pull from plugins.

This makes plugin repayment best-effort and opportunistic, but not guaranteed.

## Events and errors

Events:

- `AddPlugin(plugin)`
- `RemovePlugin(plugin)`
- `Pull(plugin, amount)`
- `Push(plugin, amount)`

Errors:

- `NotPlugin` (add: plugin not whitelisted)
- `AlreadySet` (add: already active; remove: plugin not found)
- `PluginOwe` (remove: plugin has outstanding debt)
- `PluginNotActive` (pull: fails active check)
- `FeeOnTransferNotSupported` (pull: token transfer shortfall)
- `InsufficientAmount` (pull/push: zero amount)

## Edge cases and gotchas

- **Activation guard**: `pull` reverts unless `pluginActiveSince[msg.sender] >= block.timestamp`.
  With the current code, this means a plugin can only pull in the same block timestamp
  as `addPlugin` (or when block timestamp does not advance).
- **Timestamp zero**: when `block.timestamp == 0`, `addPlugin` sets `pluginActiveSince` to `0`,
  so `addPlugin` does not prevent duplicates and `pull` can pass the active check for any address.
- **Partial pulls**: `pull` may return less than requested if `pluginsOwe` already consumes
  the vault's active stake.
- **Fee-on-transfer collateral**: `pull` explicitly rejects fee-on-transfer behavior;
  `push` does not, so accounting can drift if collateral is fee-charging.
- **Best-effort repayment**: `_pullPlugins` reduces debt only if `triggerPush` returns `true`.
  It does not verify token transfers.
- **Ordering effects**: `plugins[]` order determines repayment priority; removal swaps with last,
  so order is not stable.

## Security assumptions

- Plugins are trusted to implement `triggerPush` correctly and only return `true` after transferring collateral.
- Collateral is expected to be non-fee-on-transfer for accurate accounting.
- External plugin calls in `_pullPlugins` can fail; the vault tolerates outstanding `pluginsOwe`.
