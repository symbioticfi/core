# Hoodi Seeded V2 Deployment And Scenario Design

## Goal

Add a complete Hoodi workflow that:

- deploys a fresh V2 instance without verification
- writes a full deployed-address config to JSON
- consumes that JSON in a seeded scenario runner
- creates several randomized vaults with a couple of randomized subvaults each
- exercises the full practical action surface for VaultV2, adapters, and UniversalDelegator
- uses multicalls whenever safe to reduce transaction count
- supports both live Hoodi adapter dependencies and deterministic mock fallbacks

The result should be reusable operational scripts, not a one-off scenario.

## Scope

This work covers three script layers plus tests:

1. `script/deploy/`
   - add any missing reusable deployment scripts needed to stand up the fresh Hoodi V2 environment and any mock dependencies
2. `script/upgrade/`
   - add any missing reusable upgrade or whitelist scripts needed to complete the deployed instance cleanly
3. `script/actions/`
   - add any missing reusable operational scripts for VaultV2, adapters, and delegator slot management
4. scenario orchestration
   - add a seeded Hoodi scenario runner that consumes deployment JSON and executes the end-to-end action matrix

This work does not include contract verification for the newly deployed Hoodi instance.

## Design Principles

- Reproducible randomness: one seed must produce the same deployment-dependent scenario layout and action sequence every time.
- Separation of concerns: deployment writes JSON, scenario consumes JSON, actions remain reusable and independently callable.
- Same repo style: new scripts follow the existing base-script plus thin wrapper pattern already used in `script/deploy`, `script/upgrade`, and `script/actions`.
- Deterministic fallback: prefer live Hoodi addresses for Aave and Morpho dependencies when usable, otherwise deploy mocks and record that in JSON.
- Operational usefulness: outputs must be directly usable as deployment records and rerun inputs.

## Existing Foundation

The current branch already provides:

- `script/deploy/V2Deploy.s.sol` and `script/deploy/base/V2DeployBase.s.sol`
- `script/upgrade/V2Upgrade.s.sol` and `script/upgrade/base/V2UpgradeBase.s.sol`
- several reusable action scripts in `script/actions/`
- `MigrateToVaultV2` base script with delegator multicall usage
- Hoodi core constants in `test/integration/SymbioticCoreConstants.sol`
- integration harnesses for V2 deployment and upgrade
- adapter mocks and adapter-focused tests in `test/vault/VaultV2Adapters.t.sol`

The missing piece is a scriptable end-to-end Hoodi V2 scenario with complete reusable action coverage around it.

## Deliverables

### 1. Deployment JSON

Add a deploy path that writes a JSON artifact, for example:

- `script/output/hoodi/<seed>/deployment.json`

The artifact should include:

- chain id
- seed
- deployer
- timestamp
- selected mode for each dependency: `live` or `mock`
- core addresses used
- V2 implementation addresses
- `AdapterRegistry`
- `VaultV2Migrate`
- `VaultV2`
- `UniversalDelegator`
- `UniversalSlasher`
- rewards contract
- fee registry
- adapter addresses
- adapter dependency addresses
- all created vaults
- all created delegators
- all created slashers
- all created operator/network/staker addresses used by the scenario

### 2. Scenario JSON

Add a scenario result artifact, for example:

- `script/output/hoodi/<seed>/run.json`

The artifact should include:

- input deployment JSON path or hash
- seed
- generated topology summary
- executed actions in order
- key transaction hashes
- final addresses discovered during execution, including adapter accounts
- final state summary for each vault and delegator

### 3. Reusable Scripts

Add any missing scripts in the appropriate layer:

#### `script/deploy/`

Required additions where absent:

- deploy mock rewards or fee registry if not supplied
- deploy mock Aave dependency bundle
- deploy mock Morpho dependency bundle
- deploy adapters against either live or mock dependency addresses
- persist deployment JSON

#### `script/upgrade/`

Required additions where absent:

- whitelist or register V2 components if current reusable coverage is insufficient
- whitelist or register adapters if the final Hoodi workflow needs explicit upgrade-layer support
- persist relevant upgrade outputs into deployment JSON

#### `script/actions/`

Missing reusable actions should be added in the same style as existing scripts, including:

- `SetAdapterLimit`
- `SwapAdapters`
- `AllocateAdapter`
- `DeallocateAdapter`
- `SkimAdapters`
- `DeallocateAdapters`
- `CreateSlot`
- `SetSize`
- `SwapSlots`
- `RemoveSlot`
- `SetWithdrawalBufferSize`
- `RecoverAdapterFunds`
- `ForceDeallocateMorpho`

Thin wrapper scripts should remain configuration-driven and delegate execution to base scripts.

## Scenario Topology

The scenario runner will consume `deployment.json` and generate a seeded topology.

### Vault Generation

For a given seed, generate several vaults with bounded randomization:

- several vaults, not just one
- each vault gets a randomized but valid configuration
- each vault gets a couple of randomized subvaults
- adapters are distributed so both `AaveV3Adapter` and `MorphoVaultV2Adapter` are exercised

Guardrails:

- every generated layout must be valid under current VaultV2 and UniversalDelegator invariants
- generated slot trees must always leave at least one safe path for `setSize`, `swapSlots`, and `removeSlot`
- the scenario must intentionally create both no-adapter and adapter-backed stake exposure

### Address Actors

Generate or derive deterministic actors from the seed:

- curator/admin
- several networks
- several operators
- several stakers
- optional resolver and burner-related roles where needed

These addresses must be stored in JSON.

## Action Matrix

The scenario must cover the full practical action surface.

### Vault Actions

- deposit
- withdraw
- redeem
- instant withdraw
- claim
- multicall claim
- donate
- set adapter limits
- swap adapter order
- allocate to adapter
- deallocate from adapter
- skim adapters
- deallocate adapters

### Adapter Actions

- normal allocate and deallocate flows
- recover flow for adapters
- Morpho `forceDeallocate`
- adapter multicalls where safe
- adapter account deployment discovery and recording

### Delegator Actions

- create slots
- set sizes
- swap slots
- remove slots
- set withdrawal buffer size
- any required role-granting flows to make these actions executable

### Network And Operator Actions

- operator registration
- operator vault opt-in
- operator network opt-in
- network max limit setup
- network limit setup
- operator network share or limit setup depending on delegator shape

### Rewards Coverage

There is no separate on-branch vault-snapshot rewards module to wire directly. The scenario should therefore cover current reward behavior through:

- donation-driven vault rewards
- adapter skim-driven rewards returning to the vault
- later claim paths after withdrawal requests

## Multicall Strategy

Use multicalls to reduce transaction count whenever the contract surface supports batching cleanly.

Required uses:

- `IUniversalDelegator.multicall` for grouped slot creation and sizing
- `IVaultV2.multicall` for grouped claims and compatible vault actions
- `IAdapter.multicall` for grouped maintenance calls where ordering is safe

Do not batch actions if doing so would obscure dependencies or make failures hard to diagnose. Safety and replayability are more important than maximal batching.

## Live And Mock Dependency Strategy

The scenario should prefer live Hoodi dependencies when available and functional.

For each adapter dependency set:

- probe whether live Hoodi addresses are configured and usable
- if yes, use them
- if no, deploy mocks and continue

The chosen mode must be stored in `deployment.json`.

Mocks should be based on the existing test-side Aave and Morpho helper patterns to preserve current assumptions and reduce new logic.

## JSON Format And Persistence

Use Foundry file-write cheatcodes and keep the format stable and human-readable.

Requirements:

- pretty-printed JSON
- deterministic key naming
- one directory per seed
- additive structure so deployment and run data can be inspected independently

The deployment script writes `deployment.json`.
The scenario script reads `deployment.json`, executes, and writes `run.json`.

## Environment Handling

The current repo uses:

- `ETH_RPC_URL`
- `PRIVATE_KEY`
- `ETHERSCAN_API_KEY`
- Hoodi endpoint naming in `foundry.toml` currently points to `ETH_RPC_URL_HOODI`

The new script flow should tolerate the existing `.env` shape and resolve the Hoodi RPC naming mismatch cleanly instead of requiring manual edits every time.

## Failure Handling

The scenario runner must fail loudly and early on invalid setup, with clear categorization:

- missing deployment JSON
- malformed JSON
- chain mismatch
- unsupported live adapter dependency
- invalid generated topology
- failed transaction in a multicall batch

Where possible, log the current phase and the relevant address set before executing transactions.

## Testing Strategy

### Script Unit Coverage

For every new reusable base script:

- add or extend integration tests in `test/integration/actions/`
- verify emitted calldata targets and state effects

### Scenario Coverage

Add seeded end-to-end tests that verify:

- same seed produces the same topology
- deployment JSON is written with expected fields
- scenario JSON is written with expected fields
- both Aave and Morpho adapter paths execute
- randomized vaults and subvaults remain valid
- multicalls execute expected grouped changes
- reward paths and claim paths remain functional

### Mock Coverage

Add coverage for live-fallback logic so the seeded scenario remains runnable even when Hoodi does not expose both protocol dependencies.

## Proposed File Additions

The target file shape is:

- `script/deploy/...` new deploy helpers and wrappers
- `script/upgrade/...` new upgrade helpers and wrappers
- `script/actions/...` missing action scripts and matching base scripts
- `script/scenario/HoodiV2Scenario.s.sol`
- `script/output/hoodi/...` JSON artifacts
- `test/integration/actions/...` tests for new reusable scripts
- `test/integration/...` seeded end-to-end scenario coverage

## Out Of Scope

- contract verification for the newly deployed Hoodi instance
- unrelated refactors outside the new reusable script surface
- adding a new rewards module beyond the current donation and skim behavior

## Implementation Order

1. add the JSON persistence and deployment output path
2. add missing reusable deploy and upgrade scripts
3. add missing reusable action scripts
4. add the seeded scenario runner that consumes deployment JSON
5. add deterministic live-or-mock dependency resolution
6. add integration coverage for all new scripts
7. execute the scripts against the provided `.env` and collect final artifacts

## Success Criteria

The work is successful when:

- a fresh Hoodi V2 instance can be deployed without verification
- the deployment writes a complete JSON address artifact
- the scenario runner reads that artifact and completes a seeded multi-vault run
- both adapters are exercised through either live or mock dependencies
- the generated scenario covers the intended VaultV2, adapter, and delegator action surface
- missing operational scripts exist in the same style as the current repo
- the final Hoodi run produces a full deployed-address config and scenario result record
