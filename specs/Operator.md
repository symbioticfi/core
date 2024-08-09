## Operator

Operators are entities running infrastructure for decentralized networks within and outside of the Symbiotic ecosystem. The Symbiotic protocol creates a registry of operators, logs interactions with the protocol, and protocol participants can attach credentials and other data to operator entities. In the initial version, this encompasses operator entity metadata provided by the operators themselves, as well as data created by interacting with the Symbiotic protocol, such as:

- Networks that the operator opted into
- Associated vaults and restaked collateral from vaults
- Historical logs of slashings and all other interactions with the Symbiotic ecosystem

---

In Symbiotic, the operator can be either an EOA or a contract registered in the `OperatorRegistry`.

---

Let the vault be $V$, the delegator module of the vault is $D$ and slasher module is $S$.

To raise the stake, the operator must opt into networks and vaults by calling the `optIn()` method in the `OperatorNetworkOptInService` and `OperatorVaultOptInService` accordingly. The `OPERATOR_NETWORK_LIMIT_SET_ROLE` then allocates the stake to the operator by calling `D.setOperatorNetworkLimit()`.

---

The operator opts into the network to validate it. Based on various factors, such as reputation, stake amount, and other relevant criteria each network independently decides whether to include the operator in the active operator set or not.

---

The operator's stake becomes active and subject to slashing immediately after the opt-in process to both the network and the vault. However, the corresponding role in the vault can apply the timelock for allocating a stake for additional guarantees for operators. The slashing process is implemented in the $S$ module.

### Deploy

```shell
source .env
```

#### Deploy registry

Deployment script: [click](../script/deploy/OperatorRegistry.s.sol)

```shell
forge script script/deploy/OperatorRegistry.s.sol:OperatorRegistryScript --broadcast --rpc-url=$ETH_RPC_URL
```

#### Deploy metadata service

Deployment script: [click](../script/deploy/MetadataService.s.sol)

```shell
forge script script/deploy/MetadataService.s.sol:MetadataServiceScript 0x0000000000000000000000000000000000000000 --sig "run(address)" --broadcast --rpc-url=$ETH_RPC_URL
```

#### Deploy opt-in service

Deployment script: [click](../script/deploy/OptInService.s.sol)

```shell
forge script script/deploy/OptInService.s.sol:OptInServiceScript 0x0000000000000000000000000000000000000000 0x0000000000000000000000000000000000000000 --sig "run(address,address)" --broadcast --rpc-url=$ETH_RPC_URL
```
