## Rewards

For staker rewards calculation, the vault provides the following data:

- `activeSharesOfAt(account, timestamp)` - $\text{active}$ shares of the user at a specific timestamp
- `activeSharesAt(timestamp)` - total $\text{active}$ shares at a specific timestamp.
- Other checkpointed getters

Reward processing is not integrated into the vault's functionality. Instead, external reward contracts should manage this using the provided data.

However, we created the first version of the `IRewardsDistributor` interface to facilitate more generic reward distribution across networks.

- `IRewardsDistributor.version()` - provides a version of the interface that a particular rewards distributor uses
- `IRewardsDistributor.distributeReward(network, token, amount, timestamp)` - call to distribute `amount` of `token` on behalf of `network` using `timestamp` as a time point for calculations

The vault's rewards distributor's address can be obtained via the `rewardsDistributor()` method, which can be set by the `REWARDS_DISTRIBUTOR_SET_ROLE` holder.

### Deploy

```shell
source .env
```

#### Deploy factory

Deployment script: [click](../script/deploy/defaultRewardsDistributor/DefaultRewardsDistributorFactory.s.sol)

```shell
forge script script/deploy/defaultRewardsDistributor/DefaultRewardsDistributorFactory.s.sol:DefaultRewardsDistributorFactoryScript 0x0000000000000000000000000000000000000000 0x0000000000000000000000000000000000000000 0x0000000000000000000000000000000000000000 --sig "run(address,address,address)" --broadcast --rpc-url=$ETH_RPC_URL
```

#### Deploy entity

Deployment script: [click](../script/deploy/defaultRewardsDistributor/DefaultRewardsDistributor.s.sol)

```shell
forge script script/deploy/defaultRewardsDistributor/DefaultRewardsDistributor.s.sol:DefaultRewardsDistributorScript 0x0000000000000000000000000000000000000000 0x0000000000000000000000000000000000000000 --sig "run(address,address)" --broadcast --rpc-url=$ETH_RPC_URL
```
