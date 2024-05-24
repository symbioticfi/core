## Vault

### Deploy

```shell
$ source .env
```

#### Deploy factory

Deployment script: [click](https://github.com/symbioticfi/core-private/blob/main/script/deploy/VaultFactory.s.sol)

```shell
$ forge script script/deploy/VaultFactory.s.sol:VaultFactoryScript 0x0000000000000000000000000000000000000000 --sig "run(address)" --broadcast --rpc-url=$RPC_MAINNET
```

#### Deploy entity

Deployment script: [click](https://github.com/symbioticfi/core-private/blob/main/script/deploy/Vault.s.sol)

```shell
$ forge script script/deploy/Vault.s.sol:VaultScript 0x0000000000000000000000000000000000000000 0x0000000000000000000000000000000000000000 0x0000000000000000000000000000000000000000 1 0 0 false --sig "run(address,address,address,uint48,uint48,uint48,string,uint256,bool)" --broadcast --rpc-url=$RPC_MAINNET
```
