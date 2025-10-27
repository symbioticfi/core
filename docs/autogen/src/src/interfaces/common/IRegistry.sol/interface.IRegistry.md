# IRegistry
[Git Source](https://github.com/symbioticfi/core/blob/5ab692fe7f696ff6aee61a77fae37dc444e1c86e/src/interfaces/common/IRegistry.sol)


## Functions
### isEntity

Get if a given address is an entity.


```solidity
function isEntity(address account) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|address to check|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|if the given address is an entity|


### totalEntities

Get a total number of entities.


```solidity
function totalEntities() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|total number of entities added|


### entity

Get an entity given its index.


```solidity
function entity(uint256 index) external view returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`index`|`uint256`|index of the entity to get|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|address of the entity|


## Events
### AddEntity
Emitted when an entity is added.


```solidity
event AddEntity(address indexed entity);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`entity`|`address`|address of the added entity|

## Errors
### EntityNotExist

```solidity
error EntityNotExist();
```

