# IVaultConfigurator
[Git Source](https://github.com/symbioticfi/core/blob/4905f62919b30e0606fff3aaa7fcd52bf8ee3d3e/src/interfaces/IVaultConfigurator.sol)


## Functions
### VAULT_FACTORY

Get the vault factory's address.


```solidity
function VAULT_FACTORY() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|address of the vault factory|


### DELEGATOR_FACTORY

Get the delegator factory's address.


```solidity
function DELEGATOR_FACTORY() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|address of the delegator factory|


### SLASHER_FACTORY

Get the slasher factory's address.


```solidity
function SLASHER_FACTORY() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|address of the slasher factory|


### create

Create a new vault with a delegator and a slasher.


```solidity
function create(InitParams calldata params) external returns (address vault, address delegator, address slasher);
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


## Structs
### InitParams
Initial parameters needed for a vault with a delegator and a slasher deployment.


```solidity
struct InitParams {
    uint64 version;
    address owner;
    bytes vaultParams;
    uint64 delegatorIndex;
    bytes delegatorParams;
    bool withSlasher;
    uint64 slasherIndex;
    bytes slasherParams;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`version`|`uint64`|entity's version to use|
|`owner`|`address`|initial owner of the entity|
|`vaultParams`|`bytes`|parameters for the vault initialization|
|`delegatorIndex`|`uint64`|delegator's index of the implementation to deploy|
|`delegatorParams`|`bytes`|parameters for the delegator initialization|
|`withSlasher`|`bool`|whether to deploy a slasher or not|
|`slasherIndex`|`uint64`|slasher's index of the implementation to deploy (used only if withSlasher == true)|
|`slasherParams`|`bytes`|parameters for the slasher initialization (used only if withSlasher == true)|

