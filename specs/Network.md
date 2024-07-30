## Network

In Symbiotic, networks are represented through a network address (either an EOA or a contract) and a middleware contract, which can incorporate custom logic and is required to include slashing logic. The core protocol's fundamental functionalities encompass slashing operators and rewarding both stakers and operators.

---

A network epoch (let's name it $`\text{NETWORK\_EPOCH}`$) is a period while a certain operator set, obtained given the captured stake, operates for the good of the network. The epoch plus the vault's veto and execute phases' durations should not exceed the duration of the vault's epoch to **ensure that withdrawals do not impact the captured stake** (however, the conditions can be softer in practice).

---

The vault allocates stakes by setting limits for networks and operators.

Let the vault be $V$, the delegator module of the vault is $D$ and slasher module is $S$.

Given the current $\text{active}$ balance of the vault and the limits, we can **capture the stake for the subsequent network epoch**:

$networkOperatorStake = D.stake(network, operator)$

---

The limits are set in the vault, and the network cannot control this process (unless the vault is managed by the network). However, the **implementation prevents** the vault **from removing the previously given slashing guarantees**.

Moreover, the network **can limit the maximum amount of stake** it wants to use via the `D.setMaxNetworkLimit()` method.

---

The network has the flexibility to configure the operator set within the middleware or network contract.

The following functions could be useful:

- `D.stakeAt(network, operator, timestamp, hints)`: Determines minimum stake eligibility. Note that the sum of operators' stakes may exceed the network's total stake, depending on the network's and operators' limits in the delegator module.
- `OperatorOptInService.isOptedInAt(operator, network, timestamp, hint)`: Checks the opt-in status.

---

For each operator, the network can obtain its stake which will be valid during $d = vaultEpoch$. It can slash the whole stake of the operator. Note, that the stake itself is given according to the limits and other conditions.

Note that **the actual slashed amount may be less than the requested one**. This is influenced by the cross-slashing or veto process of the Slasher module.

The network can slash the operator within the vault only if

1. The operator is opted into the vault
2. The operator is opted into the network

To initiate a slashing process, a network should call:

1. `slash(network, operator, amount, captureTimestamp, hints)` for the Slasher module.
2. `requestSlash(network, operator, amount, captureTimestamp, hints)` for the VetoSlasher module.

The module will check the provided guarantees at the $captureTimestamp$, denoted as $G$. It also calculates cumulative slashings from the $captureTimestamp$ to the current moment, denoted as $C$. It is guaranteed that for every correct $captureTimestamp$, $C \leq G$. The module will allow slashing no more than $G - C$ to justify the given guarantees.

### Deploy

```shell
source .env
```

#### Deploy registry

Deployment script: [click](../script/deploy/NetworkRegistry.s.sol)

```shell
forge script script/deploy/NetworkRegistry.s.sol:NetworkRegistryScript --broadcast --rpc-url=$ETH_RPC_URL
```

#### Deploy metadata service

Deployment script: [click](../script/deploy/MetadataService.s.sol)

```shell
forge script script/deploy/MetadataService.s.sol:MetadataServiceScript 0x0000000000000000000000000000000000000000 --sig "run(address)" --broadcast --rpc-url=$ETH_RPC_URL
```

#### Deploy middleware service

Deployment script: [click](../script/deploy/NetworkMiddlewareService.s.sol)

```shell
forge script script/deploy/NetworkMiddlewareService.s.sol:NetworkMiddlewareServiceScript 0x0000000000000000000000000000000000000000 --sig "run(address)" --broadcast --rpc-url=$ETH_RPC_URL
```

#### Deploy opt-in service

Deployment script: [click](../script/deploy/OptInService.s.sol)

```shell
forge script script/deploy/OptInService.s.sol:OptInServiceScript 0x0000000000000000000000000000000000000000 0x0000000000000000000000000000000000000000 --sig "run(address,address)" --broadcast --rpc-url=$ETH_RPC_URL
```
