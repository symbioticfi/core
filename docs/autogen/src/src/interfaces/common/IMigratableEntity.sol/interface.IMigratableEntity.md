# IMigratableEntity
[Git Source](https://github.com/symbioticfi/core/blob/5ab692fe7f696ff6aee61a77fae37dc444e1c86e/src/interfaces/common/IMigratableEntity.sol)


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


### version

Get the entity's version.

Starts from 1.


```solidity
function version() external view returns (uint64);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint64`|version of the entity|


### initialize

Initialize this entity contract by using a given data and setting a particular version and owner.


```solidity
function initialize(uint64 initialVersion, address owner, bytes calldata data) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`initialVersion`|`uint64`|initial version of the entity|
|`owner`|`address`|initial owner of the entity|
|`data`|`bytes`|some data to use|


### migrate

Migrate this entity to a particular newer version using a given data.


```solidity
function migrate(uint64 newVersion, bytes calldata data) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newVersion`|`uint64`|new version of the entity|
|`data`|`bytes`|some data to use|


## Errors
### AlreadyInitialized

```solidity
error AlreadyInitialized();
```

### NotFactory

```solidity
error NotFactory();
```

### NotInitialized

```solidity
error NotInitialized();
```

