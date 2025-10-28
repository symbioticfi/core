# MigratablesFactory
[Git Source](https://github.com/symbioticfi/core/blob/45a7dbdd18fc5ac73ecf7310fc6816999bb8eef3/src/contracts/common/MigratablesFactory.sol)

**Inherits:**
[Registry](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/contracts/common/Registry.sol/abstract.Registry.md), Ownable, [IMigratablesFactory](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/interfaces/common/IMigratablesFactory.sol/interface.IMigratablesFactory.md)


## State Variables
### blacklisted
Get if a version is blacklisted (e.g., in case of invalid implementation).

The given version is still deployable.


```solidity
mapping(uint64 version => bool value) public blacklisted
```


### _whitelistedImplementations

```solidity
EnumerableSet.AddressSet private _whitelistedImplementations
```


## Functions
### checkVersion


```solidity
modifier checkVersion(uint64 version) ;
```

### constructor


```solidity
constructor(address owner_) Ownable(owner_);
```

### lastVersion

Get the last available version.

If zero, no implementations are whitelisted.


```solidity
function lastVersion() public view returns (uint64);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint64`|version of the last implementation|


### implementation

Get the implementation for a given version.

Reverts when an invalid version.


```solidity
function implementation(uint64 version) public view checkVersion(version) returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`version`|`uint64`|version to get the implementation for|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|address of the implementation|


### whitelist

Whitelist a new implementation for entities.


```solidity
function whitelist(address implementation_) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`implementation_`|`address`||


### blacklist

Blacklist a version of entities.

The given version will still be deployable.


```solidity
function blacklist(uint64 version) external onlyOwner checkVersion(version);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`version`|`uint64`|version to blacklist|


### create

Create a new entity at the factory.

CREATE2 salt is constructed from the given parameters.


```solidity
function create(uint64 version, address owner_, bytes calldata data) external returns (address entity_);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`version`|`uint64`|entity's version to use|
|`owner_`|`address`||
|`data`|`bytes`|initial data for the entity creation|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`entity_`|`address`|address of the entity|


### migrate

Migrate a given entity to a given newer version.

Only the entity's owner can call this function.


```solidity
function migrate(address entity_, uint64 newVersion, bytes calldata data) external checkEntity(entity_);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`entity_`|`address`||
|`newVersion`|`uint64`|new version to migrate to|
|`data`|`bytes`|some data to reinitialize the contract with|


