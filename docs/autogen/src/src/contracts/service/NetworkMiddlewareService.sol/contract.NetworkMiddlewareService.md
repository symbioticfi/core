# NetworkMiddlewareService
[Git Source](https://github.com/symbioticfi/core/blob/72d444d21da2b07516bb08def1e4b57d35cf27c3/src/contracts/service/NetworkMiddlewareService.sol)

**Inherits:**
[INetworkMiddlewareService](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/interfaces/service/INetworkMiddlewareService.sol/interface.INetworkMiddlewareService.md)


## State Variables
### NETWORK_REGISTRY
Get the network registry's address.


```solidity
address public immutable NETWORK_REGISTRY
```


### middleware
Get a given network's middleware.


```solidity
mapping(address network => address value) public middleware
```


## Functions
### constructor


```solidity
constructor(address networkRegistry) ;
```

### setMiddleware

Set a new middleware for a calling network.


```solidity
function setMiddleware(address middleware_) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`middleware_`|`address`||


