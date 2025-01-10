## Symbiotic

**Symbiotic is a shared security protocol enabling decentralized networks to control and customize their own multi-asset restaking implementation.**

Symbiotic core consists of:

- **Collateral**: a new type of asset that allows stakeholders to hold onto their funds and earn yield from them without needing to lock these funds in a direct manner or convert them to another type of asset.

- **Vaults**: the delegation and restaking management layer of Symbiotic that handles three crucial parts of the Symbiotic economy: accounting, delegation strategies, and reward distribution.

- **Operators**: entities running infrastructure for decentralized networks within and outside of the Symbiotic ecosystem.

- **Resolvers**: contracts or entities that are able to veto slashing incidents forwarded from networks and can be shared across networks.

- **Networks**: any protocols that require a decentralized infrastructure network to deliver a service in the crypto economy, e.g., enabling developers to launch decentralized applications by taking care of validating and ordering transactions, providing off-chain data to applications in the crypto economy, or providing users with guarantees about cross-network interactions, etc.

## Technical Documentation

Can be found [here](./specs).

## Security

Security audits can be found [here](./audits).

Not included files:

- [`src/contracts/hints`](src/contracts/hints)

## Usage

### Env

Create `.env` file using a template:

```
ETH_RPC_URL=
ETH_RPC_URL_HOLESKY=
ETHERSCAN_API_KEY=
```

\* ETH_RPC_URL is optional.<br/>\* ETH_RPC_URL_HOLESKY is optional.<br/>\* ETHERSCAN_API_KEY is optional.

### Build

```shell
forge build
```

### Test

```shell
forge test
```

### Format

```shell
forge fmt
```

### Gas Snapshots

```shell
forge snapshot
```
