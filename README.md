**[Symbiotic Protocol](https://symbiotic.fi) is an extremely flexible and permissionless shared security system.**

This repository contains the core Symbiotic smart contracts responsible for managing deposits, stake allocations and slashing.

[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/symbioticfi/core)

Symbiotic core consists of:

- **Collateral**: a new type of asset that allows stakeholders to hold onto their funds and earn yield from them without needing to lock these funds in a direct manner or convert them to another type of asset.

- **Vaults**: the delegation and restaking management layer of Symbiotic that handles three crucial parts of the Symbiotic economy: accounting, delegation strategies, and reward distribution.

- **Operators**: entities running infrastructure for decentralized networks within and outside of the Symbiotic ecosystem.

- **Resolvers**: contracts or entities that are able to veto slashing incidents forwarded from networks and can be shared across networks.

- **Networks**: any protocols that require a decentralized infrastructure network to deliver a service in the crypto economy, e.g., enabling developers to launch decentralized applications by taking care of validating and ordering transactions, providing off-chain data to applications in the crypto economy, or providing users with guarantees about cross-network interactions, etc.

## Documentation

- [What is Symbiotic?](https://docs.symbiotic.fi/)
- [What is Collateral?](https://docs.symbiotic.fi/modules/collateral)
- [What is Vault?](https://docs.symbiotic.fi/category/vault)

## Usage

### Dependencies

- Git ([installation](https://git-scm.com/downloads))
- Foundry ([installation](https://getfoundry.sh/introduction/installation/))

### Prerequisites

**Clone the repository**

```
git clone --recurse-submodules https://github.com/symbioticfi/core.git
```

### Deploy Your Vault

Open [`DeployVaultV2.s.sol`](./script/DeployVaultV2.s.sol), you will see config like this:

```solidity
// Name of the ERC20 representing shares of the active stake in the vault
string NAME = "SymVault";
// Symbol of the ERC20 representing shares of the active stake in the vault
string SYMBOL = "SV";
// Address of the owner of the vault who can migrate the vault to new versions whitelisted by Symbiotic
address OWNER = 0x0000000000000000000000000000000000000000;
// Address of the collateral token
address COLLATERAL = 0x0000000000000000000000000000000000000001;
// Vault's burner to send slashed funds to (e.g., 0xdEaD or some unwrapper contract; not used in case of no slasher)
address BURNER = 0x000000000000000000000000000000000000dEaD;
// Duration of the vault epoch (the withdrawal delay for staker varies from EPOCH_DURATION to 2 * EPOCH_DURATION depending on when the withdrawal is requested)
uint48 EPOCH_DURATION = 7 days;
// Initial depositor to whitelist (VaultV2 requires one non-zero address even when the deposit whitelist is disabled)
address DEPOSITOR_TO_WHITELIST = 0x0000000000000000000000000000000000000001;
// Initial withdrawal buffer size
uint128 WITHDRAWAL_BUFFER_SIZE = type(uint128).max;
// Whether to deploy a slasher
bool WITH_SLASHER = true;
// Whether slash execution should make a call to the burner on slashing
bool IS_BURNER_HOOK = BURNER != address(0);
// Duration of a veto period (should be less than EPOCH_DURATION)
uint48 VETO_DURATION = 1 days;
// Delay before a resolver update becomes active (should be greater than EPOCH_DURATION)
uint48 RESOLVER_SET_DELAY = 21 days;

// Optional

// Deposit limit (maximum amount of the active stake allowed in the vault)
uint256 DEPOSIT_LIMIT = 0;
```

Edit needed fields, and execute the script via:

```
forge script script/DeployVaultV2.s.sol --rpc-url <RPC_URL> --private-key <PRIVATE_KEY> --broadcast
```

In the console, you will see logs like these:

```bash
Deployed VaultV2
    vault:0x9c9e536A269ec83a0628404e35b2F940d7226c8C
    delegator:0xb7a105A294f7E2d399C9692c12ba4cAba90F5AAB
```

### Interact with Vaults

There are predefined V2 [action-scripts](./script/actions/v2/), that you can use from the start:

- [AddAdapter](./script/actions/v2/AddAdapter.s.sol) – add an adapter to a VaultV2 delegator
- [RemoveAdapter](./script/actions/v2/RemoveAdapter.s.sol) – remove an adapter from a VaultV2 delegator
- [SwapAdapters](./script/actions/v2/SwapAdapters.s.sol) – swap two adapters in a VaultV2 delegator
- [AllocateAdapter](./script/actions/v2/AllocateAdapter.s.sol) – allocate assets to one adapter
- [AllocateAdapterExact](./script/actions/v2/AllocateAdapterExact.s.sol) – allocate an exact amount to one adapter
- [AllocateAdapters](./script/actions/v2/AllocateAdapters.s.sol) – allocate assets across configured adapters
- [DeallocateAdapter](./script/actions/v2/DeallocateAdapter.s.sol) – deallocate assets from one adapter
- [DeallocateAdapters](./script/actions/v2/DeallocateAdapters.s.sol) – deallocate assets across configured adapters
- [DeallocateAdaptersExact](./script/actions/v2/DeallocateAdaptersExact.s.sol) – deallocate an exact amount across configured adapters
- [ForceDeallocateAdapter](./script/actions/v2/ForceDeallocateAdapter.s.sol) – force deallocation from one adapter
- [SweepPending](./script/actions/v2/SweepPending.s.sol) – settle pending adapter deallocations
- [SetAdapterLimit](./script/actions/v2/SetAdapterLimit.s.sol) – set an adapter absolute limit
- [SetAdapterLimits](./script/actions/v2/SetAdapterLimits.s.sol) – set adapter absolute and share limits
- [SetAutoAllocateAdapters](./script/actions/v2/SetAutoAllocateAdapters.s.sol) – configure auto-allocation adapters
- [RequestRedeem](./script/actions/v2/RequestRedeem.s.sol) – request a VaultV2 withdrawal
- [ClaimWithdrawal](./script/actions/v2/ClaimWithdrawal.s.sol) – claim a finalized VaultV2 withdrawal
- [SetDepositLimit](./script/actions/v2/SetDepositLimit.s.sol) – set the VaultV2 deposit limit value
- [SetIsDepositLimit](./script/actions/v2/SetIsDepositLimit.s.sol) – enable or disable the VaultV2 deposit limit
- [SetDepositWhitelist](./script/actions/v2/SetDepositWhitelist.s.sol) – enable or disable the VaultV2 deposit whitelist
- [SetDepositorWhitelistStatus](./script/actions/v2/SetDepositorWhitelistStatus.s.sol) – whitelist or unwhitelist a depositor
- [SetManagementFee](./script/actions/v2/SetManagementFee.s.sol) – set the VaultV2 management fee and receiver
- [SetPerformanceFee](./script/actions/v2/SetPerformanceFee.s.sol) – set the VaultV2 performance fee and receiver

Interaction with different actions is similar; let's consider [SetAdapterLimits](./script/actions/v2/SetAdapterLimits.s.sol) as an example:

1. Open [SetAdapterLimits.s.sol](./script/actions/v2/SetAdapterLimits.s.sol), you will see config like this:

   ```solidity
   // Address of the VaultV2
   address constant VAULT = address(0);
   // Address of the adapter to configure
   address constant ADAPTER = address(0);
   // Absolute adapter limit
   uint256 constant ABSOLUTE_LIMIT = 0;
   // Relative adapter share limit
   uint256 constant SHARE_LIMIT = 0;
   ```

2. Edit needed fields, and execute the operation:

   - If you use an EOA and want to execute the script:

     ```bash
     forge script script/actions/v2/SetAdapterLimits.s.sol --rpc-url <RPC_URL> --private-key <PRIVATE_KEY> --broadcast
     ```

   - If you use a Safe multisig and want to get a transaction calldata:

     ```bash
     forge script script/actions/v2/SetAdapterLimits.s.sol --rpc-url <RPC_URL> --sender <MULTISIG_ADDRESS> --unlocked
     ```

     In the logs, you will see the action fields and a simulation link like this:

     ```bash
     Set adapter limits
         vault:0x9c9e536A269ec83a0628404e35b2F940d7226c8C
         adapter:0x7a7ED2F93D071838b426d9aeC0368e2eB3bfE1D5
         absoluteLimit:1000000000000000000000
         shareLimit:500000
     Simulation link:
     https://dashboard.tenderly.co/TENDERLY_USERNAME/TENDERLY_PROJECT/simulator/new?network=1&contractAddress=0xb7a105A294f7E2d399C9692c12ba4cAba90F5AAB&from=0x2aCA71020De61bb532008049e1Bd41E451aE8AdC&rawFunctionInput=0x...
     ```

     In Safe->TransactionBuilder, you should:

     - enable "Custom data"
     - enter the simulation link `contractAddress` as a target address
     - use the simulation link `rawFunctionInput` as a `Data (Hex encoded)`

Moreover, a [Tenderly](https://tenderly.co/) simulation link is provided as an additional safeguard, e.g.:

```bash
Simulation link:
https://dashboard.tenderly.co/TENDERLY_USERNAME/TENDERLY_PROJECT/simulator/new?network=1&contractAddress=0xb7a105A294f7E2d399C9692c12ba4cAba90F5AAB&from=0x2aCA71020De61bb532008049e1Bd41E451aE8AdC&rawFunctionInput=0x...
```

### Build, Test, and Format

```
forge build
forge test
forge fmt
```

**Configure environment**

Create `.env` based on the template:

```
ETH_RPC_URL=
ETHERSCAN_API_KEY=
```

## Security

Security audits are aggregated in `./audits`.
