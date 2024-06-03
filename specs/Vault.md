## Vault

Vaults are the delegation and restaking management layer of Symbiotic. They handle three crucial parts of the Symbiotic economy:

- **Accounting:** vaults handle deposits, withdrawals, and slashings of collaterals and in turn their underlying assets.
- **Delegation Strategies:** vault deployers/owners define delegation and restaking strategies to operators across Symbiotic networks, which networks have to opt into.
- **Reward Distribution:** vaults distribute staking rewards from networks to collateral depositors.

Vaults are configurable and can be deployed in an immutable, pre-configured way, or specifying an owner that is able to update vault parameters. Vaults are expected to be used by operators and curators such as crypto institutions or liquid (re)staking protocols to create differentiated products, e.g.:

- **Operator-Specific Vaults:** operators may create vaults with collateral restaked to their infrastructure across any configuration of networks. An operator can create multiple vaults with differing configurations to service their clients without requiring additional node infrastructure.
- **Curated Multi-Operator Vaults:** curated configurations of restaked networks and delegation strategies to a diversified set of operators. Curated vaults can additionally set custom slashing limits to cap the collateral amount that can be slashed for specific operators or networks. The terms of these commitments need to be accepted by networks that vaults seek to provide their curation for.
- **Immutable Pre-Configured Vaults:** vaults can be deployed with pre-configured rules that cannot be updated to provide extra protection for users that are not comfortable with risks associated with their vault curator being able to add additional restaked networks or change configurations in any other way.

---

Each vault has a predefined collateral token. The address of this token can be obtained via the `collateral()` method of the vault. The collateral token must satisfy [the `ICollateral` interface](../src/interfaces/base/ICollateral.sol). All the operations and accounting within the vault are performed only with the collateral token. However, the rewards within the vault can be in different tokens. All the funds are represented in shares internally but the external interaction is done in absolute amounts of funds.

---

The size of the epoch is not specified. However, all the epochs are consecutive and have an equal constant, defined at the moment of deployment size. Next in the text, we refer to it as $\text{EPOCH}$.

#### Definitions

- $\text{active}$ balance - a pure balance of the vault/user that is not in the withdrawal process
- $\text{epoch}$ - a current epoch
- $\text{W}_\text{epoch}$ - withdrawals that will be claimable in the $\text{epoch + 1}$

#### Constraints

- $\text{totalSupply} = \text{active} + \text{W}_\text{epoch} + \text{W}_\text{epoch + 1}$ - a total amount of the collateral that can be slashed at the moment

- During withdrawal:

  1. $\text{active} \rightarrow \text{active} - \text{amount}$
  2. $\text{W}_\text{epoch + 1} \rightarrow \text{W}_\text{epoch + 1} + \text{amount}$

- During deposit:

  1. $\text{active} \rightarrow \text{active} + \text{amount}$

- During slashing:

  1. $\text{q} = \text{1} - \frac{\text{amount}}{\text{totalSupply}}$
  2. $\text{active} \rightarrow \text{active} \cdot \text{q}$
  3. $\text{W}_\text{epoch} \rightarrow \text{W}_\text{epoch} \cdot \text{q}$
  4. $\text{W}_\text{epoch + 1} \rightarrow \text{W}_\text{epoch + 1} \cdot \text{q}$

- $\forall \text{k} > \text{0}, \text{W}_\text{epoch - k}$ - claimable

- $\forall \text{k} \ge \text{0}, \text{W}_\text{epoch + k}$ - slashable and not claimable

---

Any holder of the collateral token can deposit it into the vault using the `deposit()` method of the vault. In turn, the user receives shares. Any deposit instantly increases the $\text{active}$ balance of the vault.

---

Any depositor can withdraw his funds using the `withdraw()` method of the vault. The withdrawal process consists of two parts: a **request** and a **claim**.

Consider the user **requests** the withdrawal at $\text{epoch}$. The user can **claim** the withdrawal when the $\text{epoch + 1}$ ends. Hence, a withdrawal delay varies from $\text{EPOCH + 1}$ to $\text{2} \cdot \text{EPOCH}$. Such funds are immediately reduced from the $\text{active}$ balance of the vault, however, the funds still can be slashed. **Important to note that when the $\text{epoch + 1}$ ends the funds can't be slashed anymore and can be claimed.**

---

Each slashing incident consists of 3 separate actions:

1. Request slash - `requestSlash()`
2. Veto slash - `vetoSlash()` (optional)
3. Execute slash - `executeSlash()`

The network's middleware calls the `requestSlash()` method with a given `operator`, `resolver`, and `amount`. In return, it receives the `requestIndex` of the slashing. The slashing is **not applied instantly**.

- The slashing **can be vetoed during the veto phase** by the `resolver`, and such a slashing will not be executed.
- If the veto phase is passed and the slashing is not vetoed, it can be executed via the `executeSlash()` method. Anyone can call this method after the veto phase has passed.
- Important to note that each slashing has an `executeDeadline`. If the slashing was not executed before `executeDeadline` it can't be executed anymore.

Each slashing **reduces the limits** of the slashed operator and the network requested to slash. After the slashing all the user's funds are decreased **proportionally**.

---

An operator-network limit is the maximum amount of funds the network can slash if it requests a slashing of the given operator. In other words, it means the maximum operator's stake in the network.

If such a **slashing request is executed** the operator-network **limit will be decreased** by the slashed amount. Deposits and withdrawals do not affect the limit. However, the `OPERATOR_NETWORK_LIMIT_SET_ROLE` holder can change it (decrease or increase) manually according to the $\text{totalSupply}$ of the vault and the current limits.

---

A network-resolver limit is the maximum amount of funds the network can slash if it requests a slashing with the given resolver. In other words, it means the maximum stake delegated to the network using a certain resolver.

In general, its logic is the same as for the operator-network limit. However, the `NETWORK_RESOLVER_LIMIT_SET_ROLE` holder can change it, and it can be accessed via the `networkResolverLimit()` method.

Also, each network-resolver pair has its **_max network-resolver limit_** (which is set by the network) that defines the maximum value of the network-resolver limit that can be set. It serves as a **cap of funds the network wishes to secure itself with**. It can be accessed via the `maxNetworkResolverLimit()` function.

---

A decrease in the limits produced by the appropriate role holder is not applied instantly but when the $\text{epoch + 1}$ ends (considering that it is an $\text{epoch}$ at the moment). However, an increase in the limits is an instant action.

When the network $\text{N}$ attempts to slash the given operator $\text{Op}$ with the given resolver $\text{R}$, the maximum amount of funds it can slash is the following:

$$
\text{slashableAmount} = \min (\text{totalSupply}, \min (\text{networkResolverLimit}(\text{N}, \text{R}), \text{operatorNetworkLimit}(\text{Op}, \text{N})))
$$

---

### Deploy

```shell
source .env
```

#### Deploy factory

Deployment script: [click](../script/deploy/VaultFactory.s.sol)

```shell
forge script script/deploy/VaultFactory.s.sol:VaultFactoryScript 0x0000000000000000000000000000000000000000 --sig "run(address)" --broadcast --rpc-url=$ETH_RPC_URL
```

#### Deploy entity

Deployment script: [click](../script/deploy/Vault.s.sol)

```shell
forge script script/deploy/Vault.s.sol:VaultScript 0x0000000000000000000000000000000000000000 0x0000000000000000000000000000000000000000 0x0000000000000000000000000000000000000000 1 0 0 0x0000000000000000000000000000000000000000 0 false --sig "run(address,address,address,uint48,uint48,uint48,address,uint256,bool)" --broadcast --rpc-url=$ETH_RPC_URL
```
