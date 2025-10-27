# Registry
[Git Source](https://github.com/symbioticfi/core/blob/0c5792225777a2fa2f15f10dba9650eb44861800/src/contracts/common/Registry.sol)

**Inherits:**
[IRegistry](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/interfaces/common/IRegistry.sol/interface.IRegistry.md)


## State Variables
### _entities

```solidity
EnumerableSet.AddressSet private _entities
```


## Functions
### checkEntity


```solidity
modifier checkEntity(address account) ;
```

### isEntity

Get if a given address is an entity.


```solidity
function isEntity(address entity_) public view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`entity_`|`address`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|if the given address is an entity|


### totalEntities

Get a total number of entities.


```solidity
function totalEntities() public view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|total number of entities added|


### entity

Get an entity given its index.


```solidity
function entity(uint256 index) public view returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`index`|`uint256`|index of the entity to get|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|address of the entity|


### _addEntity


```solidity
function _addEntity(address entity_) internal;
```

### _checkEntity


```solidity
function _checkEntity(address account) internal view;
```

