## Network

### Deploy

```shell
$ source .env
```

#### Deploy factory

Deployment script: [click](https://github.com/symbioticfi/core-private/blob/main/script/deploy/NetworkRegistry.s.sol)

```shell
$ forge script script/deploy/NetworkRegistry.s.sol:NetworkRegistryScript --broadcast --rpc-url=$RPC_MAINNET
```

#### Deploy metadata service

Deployment script: [click](https://github.com/symbioticfi/core-private/blob/main/script/deploy/MetadataService.s.sol)

```shell
$ forge script script/deploy/MetadataService.s.sol:MetadataServiceScript 0x0000000000000000000000000000000000000000 --sig "run(address)" --broadcast --rpc-url=$RPC_MAINNET
```

#### Deploy middleware service

Deployment script: [click](https://github.com/symbioticfi/core-private/blob/main/script/deploy/MiddlewareService.s.sol)

```shell
$ forge script script/deploy/MiddlewareService.s.sol:MiddlewareServiceScript 0x0000000000000000000000000000000000000000 --sig "run(address)" --broadcast --rpc-url=$RPC_MAINNET
```

#### Deploy opt-in service

Deployment script: [click](https://github.com/symbioticfi/core-private/blob/main/script/deploy/NetworkOptInService.s.sol)

```shell
$ forge script script/deploy/NetworkOptInService.s.sol:NetworkOptInServiceScript 0x0000000000000000000000000000000000000000 0x0000000000000000000000000000000000000000 --sig "run(address,address)" --broadcast --rpc-url=$RPC_MAINNET
```
