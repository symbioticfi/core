# IFactory
[Git Source](https://github.com/symbioticfi/core/blob/454f363c3e06eeffbe2515756b914d72c84b8ae4/src/interfaces/common/IFactory.sol)

**Inherits:**
[IRegistry](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/interfaces/common/IRegistry.sol/interface.IRegistry.md)


## Functions
### totalTypes

Get the total number of whitelisted types.


```solidity
function totalTypes() external view returns (uint64);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint64`|total number of types|


### implementation

Get the implementation for a given type.


```solidity
function implementation(uint64 type_) external view returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`type_`|`uint64`|position to get the implementation at|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|address of the implementation|


### blacklisted

Get if a type is blacklisted (e.g., in case of invalid implementation).

The given type is still deployable.


```solidity
function blacklisted(uint64 type_) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`type_`|`uint64`|type to check|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|whether the type is blacklisted|


### whitelist

Whitelist a new type of entity.


```solidity
function whitelist(address implementation) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`implementation`|`address`|address of the new implementation|


### blacklist

Blacklist a type of entity.

The given type will still be deployable.


```solidity
function blacklist(uint64 type_) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`type_`|`uint64`|type to blacklist|


### create

Create a new entity at the factory.

CREATE2 salt is constructed from the given parameters.


```solidity
function create(uint64 type_, bytes calldata data) external returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`type_`|`uint64`|type's implementation to use|
|`data`|`bytes`|initial data for the entity creation|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|address of the entity|


## Events
### Whitelist
Emitted when a new type is whitelisted.


```solidity
event Whitelist(address indexed implementation);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`implementation`|`address`|address of the new implementation|

### Blacklist
Emitted when a type is blacklisted (e.g., in case of invalid implementation).

The given type is still deployable.


```solidity
event Blacklist(uint64 indexed type_);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`type_`|`uint64`|type that was blacklisted|

## Errors
### AlreadyBlacklisted

```solidity
error AlreadyBlacklisted();
```

### AlreadyWhitelisted

```solidity
error AlreadyWhitelisted();
```

### InvalidImplementation

```solidity
error InvalidImplementation();
```

### InvalidType

```solidity
error InvalidType();
```

