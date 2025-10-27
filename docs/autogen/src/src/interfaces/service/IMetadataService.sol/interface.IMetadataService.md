# IMetadataService
[Git Source](https://github.com/symbioticfi/core/blob/df9ca184c8ea82a887fc1922bce2558281ce8e60/src/interfaces/service/IMetadataService.sol)


## Functions
### REGISTRY

Get the registry's address.


```solidity
function REGISTRY() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|address of the registry|


### metadataURL

Get a URL with an entity's metadata.


```solidity
function metadataURL(address entity) external view returns (string memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`entity`|`address`|address of the entity|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`string`|metadata URL of the entity|


### setMetadataURL

Set a new metadata URL for a calling entity.


```solidity
function setMetadataURL(string calldata metadataURL) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`metadataURL`|`string`|new metadata URL of the entity|


## Events
### SetMetadataURL
Emitted when a metadata URL is set for an entity.


```solidity
event SetMetadataURL(address indexed entity, string metadataURL);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`entity`|`address`|address of the entity|
|`metadataURL`|`string`|new metadata URL of the entity|

## Errors
### AlreadySet

```solidity
error AlreadySet();
```

### NotEntity

```solidity
error NotEntity();
```

