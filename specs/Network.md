## Network

In Symbiotic, we define networks as any protocol that requires a decentralized infrastructure network to deliver a service in the crypto economy, e.g. enabling developers to launch decentralized applications by taking care of validating and ordering transactions, providing off-chain data to applications in the crypto economy, or providing users with guarantees about cross-network interactions, etc.

---

Networks are represented through a network address (either an EOA or a contract) and a middleware contract, which can incorporate custom logic and is required to include slashing logic.

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

Deployment script: [click](../script/deploy/OptInService.s.sol)

```shell
forge script script/deploy/OptInService.s.sol:OptInServiceScript 0x0000000000000000000000000000000000000000 0x0000000000000000000000000000000000000000 --sig "run(address,address)" --broadcast --rpc-url=$ETH_RPC_URL
```
