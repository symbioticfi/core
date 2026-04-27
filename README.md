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
Deployed vault
    vault:0x9c9e536A269ec83a0628404e35b2F940d7226c8C
    delegator:0xb7a105A294f7E2d399C9692c12ba4cAba90F5AAB
    slasher:0x8D2E18628F28660cF75Ca51C85a354d7c8508B59
```

### Interact with Vaults

There are 9 predefined [action-scripts](./script/actions/), that you can use from the start:

- [RegisterOperator](./script/actions/RegisterOperator.s.sol) – register an operator in the `OperatorRegistry`
- [OptInVault](./script/actions/OptInVault.s.sol) – opt-in operator to the vault
- [OptInNetwork](./script/actions/OptInNetwork.s.sol) – opt-in operator to the network
- [SetMaxNetworkLimit](./script/actions/SetMaxNetworkLimit.s.sol) – set new [maximum network limit](https://docs.symbiotic.fi/modules/registries/#3-network-to-vault-opt-in) for the vault
- [SetNetworkLimit](./script/actions/SetNetworkLimit.s.sol) – set a [network limit](https://docs.symbiotic.fi/modules/registries/#4-vault-to-network-opt-in) (how much stake the vault curator is ready to give to the subnetwork)
- [SetOperatorNetworkShares](./script/actions/SetOperatorNetworkShares.s.sol) – set an [operator's shares for a subnetwork](https://docs.symbiotic.fi/modules/registries/#5-vault-to-operators-opt-in) (what percentage, which is equal to the shares divided by the total operators' shares, of the subnetwork's stake the vault curator is ready to give to the operator)
- [SetHook](./script/actions/SetHook.s.sol) – configure [automation hooks](https://docs.symbiotic.fi/modules/extensions/hooks) that react to slashing events
- [SetResolver](./script/actions/SetResolver.s.sol) – set a new [resolver](https://docs.symbiotic.fi/modules/counterparties/resolvers) for the vault (only if the vault uses [VetoSlasher](https://docs.symbiotic.fi/modules/vault/slashing#1-vetoslasher))
- [VetoSlash](./script/actions/VetoSlash.s.sol) – [veto a pending slash request](https://docs.symbiotic.fi/modules/vault/slashing#1-vetoslasher) during the veto period

Interaction with different actions is similar; let's consider [SetNetworkLimit](./script/actions/SetNetworkLimit.s.sol) as an example:

1. Open [SetNetworkLimit.s.sol](./script/actions/SetNetworkLimit.s.sol), you will see config like this:

   ```solidity
   // Address of the Vault
   address constant VAULT = address(0);
   // Address of the Network to set the network limit for
   address constant NETWORK = address(0);
   // Subnetwork Identifier
   uint96 constant IDENTIFIER = 0;
   // Network limit value to set
   uint256 constant LIMIT = 0;
   ```

2. Edit needed fields, and execute the operation:

   - If you use an EOA and want to execute the script:

     ```bash
     forge script script/actions/SetNetworkLimit.s.sol --rpc-url <RPC_URL> --private-key <PRIVATE_KEY> --broadcast
     ```

   - If you use a Safe multisig and want to get a transaction calldata:

     ```bash
     forge script script/actions/SetMaxNetworkLimit.s.sol --rpc-url <RPC_URL> --sender <MULTISIG_ADDRESS> --unlocked
     ```

     In the logs, you will see `data` and `target` fields like this:

     ```bash
     SetNetworkLimit data:
     data:0x02145348759d4335cb712aa188935c2bd3aa6d205ac613050000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
     target:0xd6c4b4267BFB908BBdf8C9BDa7d0Ae517aA145b0
     ```

     In Safe->TransactionBuilder, you should:

     - enable "Custom data"
     - enter `target` as a target address
     - use the `data` (e.g., `0x02145348759d4335cb712aa188935c2bd3aa6d205ac61305...`) received earlier as a `Data (Hex encoded)`

Moreover, a [Tenderly](https://tenderly.co/) simulation link is provided as an additional safeguard, e.g.:

```bash
Simulation link:
https://dashboard.tenderly.co/TENDERLY_USERNAME/TENDERLY_PROJECT/simulator/new?network=1&contractAddress=0xd6c4b4267BFB908BBdf8C9BDa7d0Ae517aA145b0&from=0x2aCA71020De61bb532008049e1Bd41E451aE8AdC&rawFunctionInput=0x02145348759d4335cb712aa188935c2bd3aa6d205ac613050000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
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
