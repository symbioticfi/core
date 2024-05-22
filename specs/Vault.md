## Vault

### Deploy

```shell
$ source .env
```

```shell
// function run(address owner)

$ forge script script/deploy/Vault.s.sol:VaultScript 0x0000000000000000000000000000000000000000  --sig "run(address)" --broadcast --rpc-url=$RPC_MAINNET
```
