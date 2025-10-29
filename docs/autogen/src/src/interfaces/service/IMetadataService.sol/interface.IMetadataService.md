# IMetadataService
[Git Source](https://github.com/symbioticfi/core/blob/f05307516bbf31fe6a8fa180eab4a8d7068a66a2/src/interfaces/service/IMetadataService.sol)


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

