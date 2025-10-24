## Symbiotic Core

**[Symbiotic Protocol](https://symbiotic.fi) is an extremely flexible and permissionless shared security system.**

This repository contains the core Symbiotic smart contracts plus deployment and operations scripts for vaults, registries, and supporting services. Use it to configure bespoke restaking flows, onboard operators, and integrate networks that rely on Symbiotic security.

[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/symbioticfi/core)

Symbiotic core consists of:

- **Collateral**: a new type of asset that allows stakeholders to hold onto their funds and earn yield from them without needing to lock these funds in a direct manner or convert them to another type of asset.

- **Vaults**: the delegation and restaking management layer of Symbiotic that handles three crucial parts of the Symbiotic economy: accounting, delegation strategies, and reward distribution.

- **Operators**: entities running infrastructure for decentralized networks within and outside of the Symbiotic ecosystem.

- **Resolvers**: contracts or entities that are able to veto slashing incidents forwarded from networks and can be shared across networks.

- **Networks**: any protocols that require a decentralized infrastructure network to deliver a service in the crypto economy, e.g., enabling developers to launch decentralized applications by taking care of validating and ordering transactions, providing off-chain data to applications in the crypto economy, or providing users with guarantees about cross-network interactions, etc.

## Documentation

- [Collateral](./specs/Collateral.md)
- [Vaults](./specs/Vault.md)
- [Operators](./specs/Operator.md)
- [Resolvers](./specs/Resolver.md)
- [Networks](./specs/Network.md)

## Usage

### Dependencies

- Git ([installation](https://git-scm.com/downloads))
- Foundry ([installation](https://getfoundry.sh/introduction/installation/))

### Prerequisites

**Clone the repository**

```
git clone --recurse-submodules https://github.com/symbioticfi/core.git
```

**Configure environment**

Create `.env` based on the template:

```
ETH_RPC_URL=
ETHERSCAN_API_KEY=
```

### Build, Test, and Format

```
forge build
forge test
forge fmt
```

### Deploy Your Vault

Open `script/deploy/DeployVault.s.sol` and update the configuration:

```solidity
    // Address of the owner of the vault who can migrate the vault to new versions whitelisted by Symbiotic
    address OWNER = 0x0000000000000000000000000000000000000000;
    // Address of the collateral token
    address COLLATERAL = 0x0000000000000000000000000000000000000000;
    // Vault's burner to send slashed funds to (e.g., 0xdEaD or some unwrapper contract; not used in case of no slasher)
    address BURNER = 0x000000000000000000000000000000000000dEaD;
    // Duration of the vault epoch (the withdrawal delay for staker varies from EPOCH_DURATION to 2 * EPOCH_DURATION depending on when the withdrawal is requested)
    uint48 EPOCH_DURATION = 7 days;
    // Type of the delegator:
    //  0. NetworkRestakeDelegator (allows restaking across multiple networks and having multiple operators per network)
    //  1. FullRestakeDelegator (do not use without knowing what you are doing)
    //  2. OperatorSpecificDelegator (allows restaking across multiple networks with only a single operator)
    //  3. OperatorNetworkSpecificDelegator (allocates the stake to a specific operator and network)
    uint64 DELEGATOR_INDEX = 0;
    // Setting depending on the delegator type:
    // 0. NetworkLimitSetRoleHolders (adjust allocations for networks)
    // 1. NetworkLimitSetRoleHolders (adjust allocations for networks)
    // 2. NetworkLimitSetRoleHolders (adjust allocations for networks)
    // 3. network (the only network that will receive the stake; should be an array with a single element)
    address[] NETWORK_ALLOCATION_SETTERS_OR_NETWORK = [0x0000000000000000000000000000000000000000];
    // Setting depending on the delegator type:
    // 0. OperatorNetworkSharesSetRoleHolders (adjust allocations for operators inside networks; in shares, resulting percentage is operatorShares / totalOperatorShares)
    // 1. OperatorNetworkLimitSetRoleHolders (adjust allocations for operators inside networks; in shares, resulting percentage is operatorShares / totalOperatorShares)
    // 2. operator (the only operator that will receive the stake; should be an array with a single element)
    // 3. operator (the only operator that will receive the stake; should be an array with a single element)
    address[] OPERATOR_ALLOCATION_SETTERS_OR_OPERATOR = [0x0000000000000000000000000000000000000000];
    // Whether to deploy a slasher
    bool WITH_SLASHER = true;
    // Type of the slasher:
    //  0. Slasher (allows instant slashing)
    //  1. VetoSlasher (allows having a veto period if the resolver is set)
    uint64 SLASHER_INDEX = 1;
    // Duration of a veto period (should be less than EPOCH_DURATION)
    uint48 VETO_DURATION = 1 days;
```

Optional parameters let you set deposit limits, whitelisted depositors, hooks, and resolver delays. After updating the script, deploy the vault with:

```
forge script script/deploy/DeployVault.s.sol --rpc-url <RPC_URL> --private-key <PRIVATE_KEY> --etherscan-api-key <ETHERSCAN_API_KEY> --broadcast --verify
```

The broadcast logs will include the vault address, delegator, and slasher instances that were deployed.

### Manage Your Deployment

Action scripts under `script/actions` cover day-to-day operations. Each script exposes a single `run(...)` entry point that sends the configured transaction using the constants you set before execution.

Available scripts:

- [RegisterOperator](./script/actions/RegisterOperator.s.sol) – register an operator in the `OperatorRegistry`.
- [OptInVault](./script/actions/OptInVault.s.sol) – opt-in operator to the vault.
- [OptInNetwork](./script/actions/OptInNetwork.s.sol) – opt-in operator to the network.
- [SetMaxNetworkLimit](./script/actions/SetMaxNetworkLimit.s.sol) – set new maximum network limit for the vault.
- [SetNetworkLimit](./script/actions/SetNetworkLimit.s.sol) – set a subnetwork's limit (how much stake the vault curator is ready to give to the subnetwork)
- [SetOperatorNetworkLimit](./script/actions/SetOperatorNetworkLimit.s.sol) – set an operator's limit for a subnetwork (how much stake the vault curator is ready to give to the operator for the subnetwork)
- [SetOperatorNetworkShares](./script/actions/SetOperatorNetworkShares.s.sol) – set an operator's shares for a subnetwork (what percentage, which is equal to the shares divided by the total operators' shares, of the subnetwork's stake the vault curator is ready to give to the operator).
- [SetHook](./script/actions/SetHook.s.sol) – configure automation hooks that react to slashing or other vault events.
- [SetResolver](./script/actions/SetResolver.s.sol) – assign resolver contract.
- [RequestSlash](./script/actions/RequestSlash.s.sol) – file a slash request against an operator, specifying subnetwork, amount, and capture timestamp.
- [ExecuteSlash](./script/actions/ExecuteSlash.s.sol) – execute an approved slash request after the veto window.
- [VetoSlash](./script/actions/VetoSlash.s.sol) – veto a pending slash request during the veto period.
- [Slash](./script/actions/Slash.s.sol) – immediate slashing when using an non-veto slasher configuration.

For multisig flows, use the `--sender <MULTISIG_ADDRESS> --unlocked` flags to retrieve calldata without broadcasting.

### Vault Configuration

Operators must opt in to both the vault and the target network before allocations take effect. Use `script/actions/OptInVault.s.sol` for operator–vault opt-ins and `script/actions/OptInNetwork.s.sol` for network opt-ins.

Stake distribution is enforced by the vault delegator. Limits are updated via:

- `SetMaxNetworkLimit` (`script/actions/SetMaxNetworkLimit.s.sol`) – callable by the network contract to define the maximum stake a vault accepts for a given identifier.
- `SetNetworkLimit`, `SetOperatorNetworkLimit`, `SetOperatorNetworkShares` – callable by the curator or configured role-holders to tune allocations.

Delegator type requirements:

- **FullRestakeDelegator** – call `SetMaxNetworkLimit`, `SetNetworkLimit`, and `SetOperatorNetworkLimit`.
- **NetworkRestakeDelegator** – call `SetMaxNetworkLimit`, `SetNetworkLimit`, and `SetOperatorNetworkShares`.
- **OperatorSpecificDelegator** – call `SetMaxNetworkLimit` and `SetNetworkLimit`.
- **OperatorNetworkSpecificDelegator** – call `SetMaxNetworkLimit` only.

## Security

Security audits are aggregated in `./audits`.
