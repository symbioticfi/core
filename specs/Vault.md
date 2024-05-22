## Vault

### Deploy

```shell
$ source .env
```

```shell
// function run(address vaultRegistry, address owner, address collateral, uint48 epochDuration, uint48 vetoDuration, uint48 slashDuration, string memory metadataURL, uint256 adminFee, bool depositWhitelist)

$ forge script script/deploy/Vault.s.sol:VaultScript 0x0000000000000000000000000000000000000000 0x0000000000000000000000000000000000000000 0x0000000000000000000000000000000000000000 1 0 0 "" false --sig "run(address,address,address,uint48,uint48,uint48,string,uint256,bool)" --broadcast --rpc-url=$RPC_MAINNET
```
