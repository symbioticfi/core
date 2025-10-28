# MetadataService
[Git Source](https://github.com/symbioticfi/core/blob/45a7dbdd18fc5ac73ecf7310fc6816999bb8eef3/src/contracts/service/MetadataService.sol)

**Inherits:**
[IMetadataService](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/interfaces/service/IMetadataService.sol/interface.IMetadataService.md)


## State Variables
### REGISTRY
Get the registry's address.


```solidity
address public immutable REGISTRY
```


### metadataURL
Get a URL with an entity's metadata.


```solidity
mapping(address entity => string value) public metadataURL
```


## Functions
### constructor


```solidity
constructor(address registry) ;
```

### setMetadataURL

Set a new metadata URL for a calling entity.


```solidity
function setMetadataURL(string calldata metadataURL_) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`metadataURL_`|`string`||


