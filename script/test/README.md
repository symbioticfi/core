# Script Test Harness

## Universal_Delegator

### Start Anvil

```bash
anvil --chain-id 31337
```

Copy the private key of Anvil account #0 from the Anvil output.

### Deploy a UniversalDelegator for the UI

```bash
forge script script/test/UniversalDelegator.s.sol:UniversalDelegatorUiSetup \
  --rpc-url http://127.0.0.1:8545 \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  --broadcast
```

The script prints `UniversalDelegator instance (proxy)` — paste that address into the UI configurator.
