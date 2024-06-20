## Rewards

For staker rewards calculation, the vault provides the following data:

- `activeSharesOfAt(account, timestamp)` - $\text{active}$ shares of the user at a specific timestamp
- `activeSharesAt(timestamp)` - total $\text{active}$ shares at a specific timestamp.
- Other checkpointed getters

Reward processing is not integrated into the vault's functionality. Instead, external reward contracts should manage this using the provided data.

However, we created the first version of the `IStakerRewardsDistributor` interface to facilitate more generic reward distribution across networks.

- `IStakerRewardsDistributor.version()` - provides a version of the interface that a particular rewards distributor uses
- `IStakerRewardsDistributor.distributeReward(network, token, amount, timestamp)` - call to distribute `amount` of `token` on behalf of `network` using `timestamp` as a time point for calculations

The vault's rewards distributor's address can be obtained via the `stakerRewardsDistributor()` method, which can be set by the `STAKER_REWARDS_DISTRIBUTOR_SET_ROLE` holder.

### Deploy

```shell
source .env
```

#### Deploy factory

Deployment script: [click](../script/deploy/defaultStakerRewardsDistributor/DefaultStakerRewardsDistributorFactory.s.sol)

```shell
forge script script/deploy/defaultStakerRewardsDistributor/DefaultStakerRewardsDistributorFactory.s.sol:DefaultStakerRewardsDistributorFactoryScript 0x0000000000000000000000000000000000000000 0x0000000000000000000000000000000000000000 0x0000000000000000000000000000000000000000 --sig "run(address,address,address)" --broadcast --rpc-url=$ETH_RPC_URL
```

#### Deploy entity

Deployment script: [click](../script/deploy/defaultStakerRewardsDistributor/DefaultStakerRewardsDistributor.s.sol)

```shell
forge script script/deploy/defaultStakerRewardsDistributor/DefaultStakerRewardsDistributor.s.sol:DefaultStakerRewardsDistributorScript 0x0000000000000000000000000000000000000000 0x0000000000000000000000000000000000000000 --sig "run(address,address)" --broadcast --rpc-url=$ETH_RPC_URL
```
