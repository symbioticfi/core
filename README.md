## Symbiotic

**Symbiotic is a shared security protocol enabling decentralized networks to control and customize their own multi-asset restaking implementation.**

### 🌟 Core Components

The Symbiotic core consists of:

#### 1. Collateral
A new type of asset that allows stakeholders to:
- Maintain control over their funds
- Earn yield without direct locking
- Avoid conversion to other asset types

#### 2. Vaults
The delegation and restaking management layer handling:
- Accounting
- Delegation strategies
- Reward distribution

#### 3. Operators
Entities running infrastructure for decentralized networks within and outside of the Symbiotic ecosystem.

#### 4. Resolvers
Contracts or entities that:
- Can veto slashing incidents
- Are shareable across networks

#### 5. Networks
Protocols requiring decentralized infrastructure for:
- Transaction validation and ordering
- Off-chain data provision
- Cross-network interaction guarantees

### 📚 Documentation

- [Technical Documentation](./specs)
- [Security Audits](./audits)

### 🔒 Security

Excluded files:
- [`src/contracts/hints`](src/contracts/hints)

### 🛠 Usage

#### Environment Setup

Create `.env` file using this template:

```env
ETH_RPC_URL=                  # Optional: Ethereum RPC URL
ETH_RPC_URL_HOLESKY=         # Optional: Holesky testnet URL
ETHERSCAN_API_KEY=           # Optional: Etherscan API key
```

#### Developer Commands

```shell
forge build    # Build the project
forge test     # Run tests
forge fmt      # Format code
forge snapshot # Create gas snapshot
```

### 🤝 Contributing

We welcome community contributions! Please review our contribution guidelines before submitting PRs.
