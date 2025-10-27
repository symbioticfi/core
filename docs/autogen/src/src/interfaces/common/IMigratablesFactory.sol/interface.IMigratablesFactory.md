# IMigratablesFactory
[Git Source](https://github.com/symbioticfi/core/blob/34733e78ecb0c08640f857df155aa6d467dd9462/src/interfaces/common/IMigratablesFactory.sol)

**Inherits:**
[IRegistry](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/interfaces/common/IRegistry.sol/interface.IRegistry.md)


## Functions
### lastVersion

Get the last available version.

If zero, no implementations are whitelisted.


```solidity
function lastVersion() external view returns (uint64);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint64`|version of the last implementation|


### implementation

Get the implementation for a given version.

Reverts when an invalid version.


```solidity
function implementation(uint64 version) external view returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`version`|`uint64`|version to get the implementation for|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|address of the implementation|


### blacklisted

Get if a version is blacklisted (e.g., in case of invalid implementation).

The given version is still deployable.


```solidity
function blacklisted(uint64 version) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`version`|`uint64`|version to check|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|whether the version is blacklisted|


### whitelist

Whitelist a new implementation for entities.


```solidity
function whitelist(address implementation) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`implementation`|`address`|address of the new implementation|


### blacklist

Blacklist a version of entities.

The given version will still be deployable.


```solidity
function blacklist(uint64 version) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`version`|`uint64`|version to blacklist|


### create

Create a new entity at the factory.

CREATE2 salt is constructed from the given parameters.


```solidity
function create(uint64 version, address owner, bytes calldata data) external returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`version`|`uint64`|entity's version to use|
|`owner`|`address`|initial owner of the entity|
|`data`|`bytes`|initial data for the entity creation|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|address of the entity|


### migrate

Migrate a given entity to a given newer version.

Only the entity's owner can call this function.


```solidity
function migrate(address entity, uint64 newVersion, bytes calldata data) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`entity`|`address`|address of the entity to migrate|
|`newVersion`|`uint64`|new version to migrate to|
|`data`|`bytes`|some data to reinitialize the contract with|


## Events
### Whitelist
Emitted when a new implementation is whitelisted.


```solidity
event Whitelist(address indexed implementation);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`implementation`|`address`|address of the new implementation|

### Blacklist
Emitted when a version is blacklisted (e.g., in case of invalid implementation).

The given version is still deployable.


```solidity
event Blacklist(uint64 indexed version);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`version`|`uint64`|version that was blacklisted|

### Migrate
Emitted when an entity is migrated to a new version.


```solidity
event Migrate(address indexed entity, uint64 newVersion);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`entity`|`address`|address of the entity|
|`newVersion`|`uint64`|new version of the entity|

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

### InvalidVersion

```solidity
error InvalidVersion();
```

### NotOwner

```solidity
error NotOwner();
```

### OldVersion

```solidity
error OldVersion();
```

