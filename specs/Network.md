## Network

In Symbiotic, we define networks as any protocol that requires a decentralized infrastructure network to deliver a service in the crypto economy, e.g. enabling developers to launch decentralized applications by taking care of validating and ordering transactions, providing off-chain data to applications in the crypto economy, or providing users with guarantees about cross-network interactions, etc.

---

Networks are represented through a network address (either an EOA or a contract) and a middleware contract, which can incorporate custom logic and is required to include slashing logic.

---

The network epoch (let's name it $`\text{NETWORK\_EPOCH}`$) plus the vault's veto and execute phases' durations should not exceed the duration of the vault's epoch to **ensure that withdrawals do not impact the captured stake** (however, the conditions can be softer in practice):

- $`
  \text{CYCLE\_DURATION} = \text{NETWORK\_EPOCH} + \text{vetoDuration} + \text{executeDuration}
  `$
- $`
  \text{CYCLE\_DURATION} <= \text{EPOCH}
  `$

---

The vault allocates stakes by setting limits for network-resolver and operator-network pairs.

Given the current $active$ balance of the vault and the limits, we can **capture the stake for the subsequent network epoch**:

$`
\text{networkStake} = \min \left(
\begin{array}{l}
\text{activeSupply}, \\
\sum_{\text{resolver}} \left\{
    \min \left(
    \begin{array}{l}
        \text{networkResolverLimit}, \\
        \text{networkResolverLimitIn}(\text{CYCLE\_DURATION})
    \end{array}
    \right)
\right\}, \\
\sum_{\text{operator}} \left\{
    \min \left(
    \begin{array}{l}
        \text{operatorNetworkLimit}, \\
        \text{operatorNetworkLimitIn}(\text{CYCLE\_DURATION})
    \end{array}
    \right)
\right\}
\end{array}
\right)
`$

---

The limits are set in the vault, and the network cannot control this process (unless the vault is managed by the network). However, the **realization prevents** the vault **from removing the previously given slashing guarantees**.

---

$$
    \text{slashableAmount}(\text{resolver}, \text{operator}) = \min(\text{totalSupply}, \text{networkResolverLimit}, \text{operatorNetworkLimit})
$$

Note that **the actual slashed amount may be less than the requested one**. This is influenced by updating the network-resolver and operator-network limits, as well as by the cross-slashing. Limits can be updated between the time of the slash request and its execution (i.e., $\text{requestTime} + \text{vetoDuration}$ and $\text{requestTime} + \text{vetoDuration} + \text{executeDuration}$). These limit updates can be observed in `Vault.nextNetworkResolverLimit()` and `Vault.nextOperatorNetworkLimit()`.

**The network cannot slash if it is not opted-in**. Also, it is important to note that **an operator cannot be slashed if he was not opted-in before the start of the previous epoch**.

---

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

Deployment script: [click](../script/deploy/NetworkOptInService.s.sol)

```shell
forge script script/deploy/NetworkOptInService.s.sol:NetworkOptInServiceScript 0x0000000000000000000000000000000000000000 0x0000000000000000000000000000000000000000 --sig "run(address,address)" --broadcast --rpc-url=$ETH_RPC_URL
```
