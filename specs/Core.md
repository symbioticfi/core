## Core

### Deploy

```shell
$ source .env
```

```shell
// function run(address owner)

$ forge script script/deploy/Core.s.sol:CoreScript 0x0000000000000000000000000000000000000000  --sig "run(address)" --broadcast --rpc-url=$RPC_MAINNET
```
