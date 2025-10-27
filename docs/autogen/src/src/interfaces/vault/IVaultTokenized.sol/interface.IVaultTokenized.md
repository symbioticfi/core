# IVaultTokenized
[Git Source](https://github.com/symbioticfi/core/blob/4905f62919b30e0606fff3aaa7fcd52bf8ee3d3e/src/interfaces/vault/IVaultTokenized.sol)

**Inherits:**
[IVault](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/interfaces/vault/IVault.sol/interface.IVault.md)


## Structs
### InitParamsTokenized
Initial parameters needed for a tokenized vault deployment.


```solidity
struct InitParamsTokenized {
    InitParams baseParams;
    string name;
    string symbol;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`baseParams`|`InitParams`|initial parameters needed for a vault deployment (InitParams)|
|`name`|`string`|name for the ERC20 tokenized vault|
|`symbol`|`string`|symbol for the ERC20 tokenized vault|

