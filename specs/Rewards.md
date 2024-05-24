## Rewards

### Deploy

```shell
$ source .env
```

#### Deploy factory

Deployment script: [click](https://github.com/symbioticfi/core-private/blob/main/script/deploy/defaultRewardsDistributor/DefaultCollateralFactory.s.sol)

```shell
$ forge script script/deploy/defaultRewardsDistributor/DefaultCollateralFactory.s.sol:DefaultCollateralFactoryScript 0x0000000000000000000000000000000000000000 0x0000000000000000000000000000000000000000 0x0000000000000000000000000000000000000000 --sig "run(address,address,address)" --broadcast --rpc-url=$RPC_MAINNET
```

#### Deploy entity

Deployment script: [click](https://github.com/symbioticfi/core-private/blob/main/script/deploy/defaultRewardsDistributor/DefaultCollateral.s.sol)

```shell
$ forge script script/deploy/defaultRewardsDistributor/DefaultCollateral.s.sol:DefaultCollateralScript 0x0000000000000000000000000000000000000000 --sig "run(address)" --broadcast --rpc-url=$RPC_MAINNET
```
