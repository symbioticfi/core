# VaultConfigurator
[Git Source](https://github.com/symbioticfi/core/blob/4905f62919b30e0606fff3aaa7fcd52bf8ee3d3e/src/contracts/VaultConfigurator.sol)

**Inherits:**
[IVaultConfigurator](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/interfaces/IVaultConfigurator.sol/interface.IVaultConfigurator.md)


## State Variables
### VAULT_FACTORY
Get the vault factory's address.


```solidity
address public immutable VAULT_FACTORY
```


### DELEGATOR_FACTORY
Get the delegator factory's address.


```solidity
address public immutable DELEGATOR_FACTORY
```


### SLASHER_FACTORY
Get the slasher factory's address.


```solidity
address public immutable SLASHER_FACTORY
```


## Functions
### constructor


```solidity
constructor(address vaultFactory, address delegatorFactory, address slasherFactory) ;
```

### create

Create a new vault with a delegator and a slasher.


```solidity
function create(InitParams memory params) public returns (address vault, address delegator, address slasher);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`params`|`InitParams`|initial parameters needed for a vault with a delegator and a slasher deployment|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`vault`|`address`|address of the vault|
|`delegator`|`address`|address of the delegator|
|`slasher`|`address`|address of the slasher|


