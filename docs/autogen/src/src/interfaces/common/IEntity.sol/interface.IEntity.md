# IEntity
[Git Source](https://github.com/symbioticfi/core/blob/4905f62919b30e0606fff3aaa7fcd52bf8ee3d3e/src/interfaces/common/IEntity.sol)


## Functions
### FACTORY

Get the factory's address.


```solidity
function FACTORY() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|address of the factory|


### TYPE

Get the entity's type.


```solidity
function TYPE() external view returns (uint64);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint64`|type of the entity|


### initialize

Initialize this entity contract by using a given data.


```solidity
function initialize(bytes calldata data) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`data`|`bytes`|some data to use|


## Errors
### NotInitialized

```solidity
error NotInitialized();
```

