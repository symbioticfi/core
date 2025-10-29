# INetworkMiddlewareService
[Git Source](https://github.com/symbioticfi/core/blob/f05307516bbf31fe6a8fa180eab4a8d7068a66a2/src/interfaces/service/INetworkMiddlewareService.sol)


## Functions
### NETWORK_REGISTRY

Get the network registry's address.


```solidity
function NETWORK_REGISTRY() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|address of the network registry|


### middleware

Get a given network's middleware.


```solidity
function middleware(address network) external view returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`network`|`address`|address of the network|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|middleware of the network|


### setMiddleware

Set a new middleware for a calling network.


```solidity
function setMiddleware(address middleware) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`middleware`|`address`|new middleware of the network|


## Events
### SetMiddleware
Emitted when a middleware is set for a network.


```solidity
event SetMiddleware(address indexed network, address middleware);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`network`|`address`|address of the network|
|`middleware`|`address`|new middleware of the network|

## Errors
### AlreadySet

```solidity
error AlreadySet();
```

### NotNetwork

```solidity
error NotNetwork();
```

