## Operator

### Deploy

```shell
$ source .env
```

#### Deploy factory

Deployment script: [click](https://github.com/symbioticfi/core-private/blob/main/script/deploy/OperatorRegistry.s.sol)

```shell
$ forge script script/deploy/OperatorRegistry.s.sol:OperatorRegistryScript --broadcast --rpc-url=$RPC_MAINNET
```

#### Deploy metadata service

Deployment script: [click](https://github.com/symbioticfi/core-private/blob/main/script/deploy/MetadataService.s.sol)

```shell
$ forge script script/deploy/MetadataService.s.sol:MetadataServiceScript 0x0000000000000000000000000000000000000000 --sig "run(address)" --broadcast --rpc-url=$RPC_MAINNET
```

#### Deploy opt-in service

Deployment script: [click](https://github.com/symbioticfi/core-private/blob/main/script/deploy/OperatorOptInService.s.sol)

```shell
$ forge script script/deploy/OperatorOptInService.s.sol:OperatorOptInServiceScript 0x0000000000000000000000000000000000000000 0x0000000000000000000000000000000000000000 --sig "run(address,address)" --broadcast --rpc-url=$RPC_MAINNET
```
