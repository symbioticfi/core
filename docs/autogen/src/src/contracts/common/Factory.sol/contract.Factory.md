# Factory
[Git Source](https://github.com/symbioticfi/core/blob/f05307516bbf31fe6a8fa180eab4a8d7068a66a2/src/contracts/common/Factory.sol)

**Inherits:**
[Registry](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/contracts/common/Registry.sol/abstract.Registry.md), Ownable, [IFactory](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/interfaces/common/IFactory.sol/interface.IFactory.md)


## State Variables
### blacklisted
Get if a type is blacklisted (e.g., in case of invalid implementation).

The given type is still deployable.


```solidity
mapping(uint64 type_ => bool value) public blacklisted
```


### _whitelistedImplementations

```solidity
EnumerableSet.AddressSet private _whitelistedImplementations
```


## Functions
### checkType


```solidity
modifier checkType(uint64 type_) ;
```

### constructor


```solidity
constructor(address owner_) Ownable(owner_);
```

### totalTypes

Get the total number of whitelisted types.


```solidity
function totalTypes() public view returns (uint64);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint64`|total number of types|


### implementation

Get the implementation for a given type.


```solidity
function implementation(uint64 type_) public view returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`type_`|`uint64`|position to get the implementation at|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|address of the implementation|


### whitelist

Whitelist a new type of entity.


```solidity
function whitelist(address implementation_) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`implementation_`|`address`||


### blacklist

Blacklist a type of entity.

The given type will still be deployable.


```solidity
function blacklist(uint64 type_) external onlyOwner checkType(type_);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`type_`|`uint64`|type to blacklist|


### create

Create a new entity at the factory.

CREATE2 salt is constructed from the given parameters.


```solidity
function create(uint64 type_, bytes calldata data) external returns (address entity_);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`type_`|`uint64`|type's implementation to use|
|`data`|`bytes`|initial data for the entity creation|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`entity_`|`address`|address of the entity|


