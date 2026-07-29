# Emergency Account and Adapter Freeze Implementations

## Goal

Add migration-compatible dummy implementations that governance can use to freeze an Account or Adapter proxy during an emergency. Add Foundry deployment scripts for each implementation.

## Scope

- `script/deploy/adapters/pause/contracts/AccountPause.sol`
- `script/deploy/adapters/pause/contracts/AdapterPause.sol`
- `script/deploy/adapters/pause/DeployAccountPause.s.sol`
- `script/deploy/adapters/pause/DeployAdapterPause.s.sol`
- Focused Foundry tests under `test/deploy/adapters/pause/`

The change will not modify the production `Account` or `Adapter` base contracts, factory contracts, or governance proposal code.

## Contract Design

`AccountPause` and `AdapterPause` will each inherit `MigratableEntity` and accept the target factory address in the constructor. This preserves the governance and migration lifecycle required by `MigratablesFactory`:

- `FACTORY()` matches the factory that will whitelist the pause implementation.
- `owner()` remains readable for the factory's migration authorization check.
- Migration into the pause implementation can complete.
- `version()` remains readable so the proxy can later migrate to a recovery implementation.

Every Account or Adapter business call will reach a fallback that unconditionally reverts. This freezes all current and future business-function selectors without copying their interfaces or changing production contracts. Inherited governance and migration functions remain available so the freeze can be managed and later reversed.

Each dummy contract will have NatSpec explaining that it is an emergency-freeze implementation intended to be deployed and activated through a governance proposal.

## Deployment Scripts

`DeployAccountPauseScript` and `DeployAdapterPauseScript` will accept an existing factory address, deploy the corresponding pause implementation, validate that its immutable `FACTORY()` value matches the input, and log the deployed address.

The scripts will not whitelist the implementation or migrate any proxy. Those state changes belong to the separately reviewed emergency governance proposal.

Because `FACTORY` is immutable, each factory requires its own pause-implementation deployment.

## Failure Behavior

- A zero factory address is rejected before broadcasting.
- Every Account/Adapter business call made through a migrated proxy reverts.
- Initialization remains disabled on the implementation.
- Unauthorized migration continues to revert through `MigratableEntity`.

## Verification

Foundry tests will demonstrate:

1. Each deployment script creates the requested pause implementation with the correct `FACTORY`.
2. A factory can whitelist the implementation and migrate an existing proxy into it.
3. Representative Account and Adapter view and state-changing selectors revert after the migration.
4. An arbitrary selector also reverts, proving coverage is not limited to the current ABI.
5. The frozen proxy can migrate to a later valid implementation, proving the emergency freeze is recoverable.

The focused test file and the repository's relevant Foundry suite will be run before completion.

## Non-Goals

- Automatically executing the governance proposal.
- Adding role-specific pause controls.
- Preserving business-function reads while frozen.
- Refactoring existing deployment infrastructure.
