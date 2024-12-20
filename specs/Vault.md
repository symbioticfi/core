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

Each vault has a predefined collateral token. The address of this token can be obtained via the `collateral()` method of the vault. The collateral token must satisfy the `IERC20` interface. All the operations and accounting within the vault are performed only with the collateral token. However, the rewards within the vault can be in different tokens. All the funds are represented in shares internally but the external interaction is done in absolute amounts of funds.

The Vault contract consists of three modules:

1. Accounting
2. Slashing logic
3. Limits and delegation logic

Accounting is performed within the vault itself. Slashing logic is handled by the Slasher module. One important aspect not yet mentioned is the validation of slashing requirements.

When a slashing request is sent, the system verifies its validity. Specifically, it checks that the operator is opted into the vault, and is interacting with the network.

We use separate OptIn service contracts to connect vaults, operators, and networks.

1. The operator must be opted into the vault.
2. The operator must be opted into the network.

These connections are made using OptIn service contracts.

If all opt-ins are confirmed, the operator is considered to be working with the network through the vault as a stake provider. Only then can the operator be slashed.

To get guarantees, the network calls the Delegator module. In case of slashing, it calls the Slasher module, which will then call the Vault and the Delegator module. This module also checks the provided guarantees as well as the slashed amount of funds to ensure it does not exceed the guaranteed amount.

---

A network can use flexible mechanics to keep its operator set state up-to-date, e.g., it’s convenient to use a conveyor approach for updating the stakes while keeping slashing guarantees for every particular version of the operator set:

1. At the beginning of every epoch the network can capture the state from vaults and their stake amount (this doesn’t require any on-chain interactions).
2. After this, the network will have slashing guarantees until the end of the next epoch, so it can use this state at least for one epoch.
3. When the epoch finishes and a slashing incident has taken place, the network will have time not less than a single epoch to request-veto-execute slash and go back to step 1 in parallel.

---

The size of the epoch is not specified. However, all the epochs are consecutive and have an equal constant, defined at the moment of deployment size. Next in the text, we refer to it as $\text{EPOCH}$.

#### Definitions

- $\text{active}$ balance - a pure balance of the vault/user that is not in the withdrawal process
- $\text{epoch}$ - a current epoch
- $\text{W}_\text{epoch}$ - withdrawals that will be claimable in the $\text{epoch + 1}$

#### Constraints

- $`\text{totalSupply} = \text{active} + \text{W}_\text{epoch} + \text{W}_\text{epoch + 1}`$ - a total amount of the collateral that can be slashed at the moment

- During withdrawal:

  1. $\text{active} \rightarrow \text{active} - \text{amount}$
  2. $`\text{W}_\text{epoch + 1} \rightarrow \text{W}_\text{epoch + 1} + \text{amount}`$

- During deposit:

  1. $\text{active} \rightarrow \text{active} + \text{amount}$

- During slashing:

  1. $\text{q} = \text{1} - \frac{\text{amount}}{\text{totalSupply}}$
  2. $\text{active} \rightarrow \text{active} \cdot \text{q}$
  3. $`\text{W}_\text{epoch} \rightarrow \text{W}_\text{epoch} \cdot \text{q}`$
  4. $`\text{W}_\text{epoch + 1} \rightarrow \text{W}_\text{epoch + 1} \cdot \text{q}`$

- $\forall \text{k} > \text{0}, \text{W}_\text{epoch - k}$ - claimable

- $\forall \text{k} \ge \text{0}, \text{W}_\text{epoch + k}$ - slashable and not claimable

---

Any holder of the collateral token can deposit it into the vault using the `deposit()` method of the vault. In turn, the user receives shares. Any deposit instantly increases the $\text{active}$ balance of the vault.

---

Any depositor can withdraw his funds using the `withdraw()` method of the vault. The withdrawal process consists of two parts: a **request** and a **claim**.

Consider the user **requests** the withdrawal at $\text{epoch}$. The user can **claim** the withdrawal when the $\text{epoch + 1}$ ends. Hence, a withdrawal delay varies from $\text{EPOCH + 1}$ to $\text{2} \cdot \text{EPOCH}$. Such funds are immediately reduced from the $\text{active}$ balance of the vault, however, the funds still can be slashed. **Important to note that when the $\text{epoch + 1}$ ends the funds can't be slashed anymore and can be claimed.**

---

In the Symbiotic protocol, a slasher module is optional. However, the text below describes the core principles when the vault has a slasher module.

Consider the network captures the stake of the operator at moment $t$. To do so, it calls the $stakeAt $ function with a given network, operator, and $timestamp$ (moment of capturing guarantees). Let $S$ be the resulting stake. This value is valid for $d$ = EPOCH_SIZE time. From this point, the pair $(S, t)$ is a guarantee given by the vault to the network. The guarantee is valid from the $timestamp $ moment to $timestamp + d$.

Essentially, slashing is the enforcement of the guarantees described above. Currently, there are two types of slashing: instant and veto-slashing.

#### Instant slashing

Instant slashing is executed immediately when a request comes in.

#### Veto slashing

Veto slashing consists of two stages: the Veto Phase and the Execute Phase.

After submitting a slashing request, there is a period of V time to issue a veto on the slashing. The veto can be made by designated participants in the vault, known as resolvers. If the slashing is not resolved after this phase, there is a period of E time to execute the slashing. Any participant can execute it. The network must consider how much time is left until the end of the guarantee before sending the slashing request.

---

Delegator is a separate module that connects to the Vault. The purpose of this module is to set limits for operators and networks, with the limits representing the operators' stake and the networks' stake. Currently, there are two types of delegators implemented:

1. FullRestakeDelegator
2. NetworkRestakeDelegator

Symbiotic is a restaking protocol, and these modules differ in how the restaking process is carried out. The modules will be described further:

There are obvious re-staking trade-offs with cross-slashing when stake can be reduced asynchronously. Networks should manage these risks by:

1. Maintaining a safe re-staking ratio.
2. Choosing the right stake-capturing ratio to minimize reaction time.

Here we describe common technical information for both modules.

Let $NL_{j}$ be the limit of the $j^{th}$ network. This limit can be considered as the network's stake, meaning the amount of funds delegated to the network. $NL_{j}$ is set by a special role in the delegator module. However, the module normalizes it. Let the vault’s active supply be $AS$.

Then $NS_{j} = \min(NL_{j}, AS)$ - network stake.

Additionally, the modules have a max network limit $mNL_{j}$, which is set by the networks themselves. This serves as the maximum possible amount of funds that can be delegated to the network. It is guaranteed that $NL_{j} \leq mNL_{j}$. This limit is mainly used by networks to manage a safe restaking ratio.

If the $i^{th}$ operator is slashed by $x$ in the $j^{th}$ network his stake can be decreased:

$NL_{j}(new) = NL_{j} - x$

Also, it should be mentioned that in the case of slashing, these modules have special hooks that call the method to process the change of limits. In general, we don't need such a method to exist because all the limits can be changed manually and instantly w/o changing already given guarantees.

#### NetworkRestakeDelegator

The main goal of this delegator is to allow restaking between multiple networks but restrict operators from being restaked within the same network. The operators' stakes are represented as shares in the network's stake.

Each network's stakes are divided across operators.

Let the $i^{th}$ operator’s share in the $j^{th}$ network be $\lambda_{i, j}$.

Then

1. $\lambda_{i, j} \cdot NS_{j}$ - the $i^{th}$ operator’s stake in the $j^{th}$ network
2. $\sum_{i}\lambda_{i, j} \cdot NS_{j} = NS_{j}$

We can conclude that slashing decreases the share of a specific operator and does not affect other operators in the same network. However, the $TS$ of the vault will decrease after slashing, which can cause other $NS_{j'}$ for $j' \neq j$ to decrease.

#### FullRestakeDelegator

This module performs restaking for both operators and networks simultaneously. The stake in the vault is shared between operators and networks. The designated role can change these stakes. If a network slashes an operator, it may cause a decrease in the stake of other restaked operators even in the same network. However, it depends on the distribution of the stakes in the module.

In this module, we introduce so-called limits for operators. Each operator has its own limit in every network.

Let the $i^{th}$ operator’s limit in the $j^{th}$ network be $OpL_{i, j}$. Such a limit is considered as a stake of the operators.

$OpS_{i, j} = min(OpL_{i, j}, NS_j)$ - the $i^{th}$ operator’s stake in the $j^{th}$ network

As already stated, this module enables restaking for operators. This means the sum of operators' stakes in the network can exceed the network’s own stake. This module is useful when operators have an insurance fund for slashing and are curated by a trusted party.

Such a slashing can lead to a situation where all the other operators' stakes will decrease.

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

_Common Vault_

Deployment script: [click](../script/deploy/Vault.s.sol)

```shell
forge script script/deploy/Vault.s.sol:VaultScript 0x0000000000000000000000000000000000000000 0x0000000000000000000000000000000000000000 0x0000000000000000000000000000000000000000 0x0000000000000000000000000000000000000000 1 false 0 0 0x0000000000000000000000000000000000000000 0x0000000000000000000000000000000000000000 false 0 0 --sig "run(address,address,address,address,uint48,bool,uint256,uint64,address,address,bool,uint64,uint48)" --broadcast --rpc-url=$ETH_RPC_URL
```

_Tokenized Vault_

Deployment script: [click](../script/deploy/VaultTokenized.s.sol)

```shell
forge script script/deploy/VaultTokenized.s.sol:VaultTokenizedScript 0x0000000000000000000000000000000000000000 0x0000000000000000000000000000000000000000 0x0000000000000000000000000000000000000000 0x0000000000000000000000000000000000000000 1 false 0 Test TEST 0 0x0000000000000000000000000000000000000000 0x0000000000000000000000000000000000000000 false 0 0 --sig "run(address,address,address,address,uint48,bool,uint256,string,string,uint64,address,address,bool,uint64,uint48)" --broadcast --rpc-url=$ETH_RPC_URL
```
