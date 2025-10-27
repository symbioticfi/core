# INetworkMiddlewareService
[Git Source](https://github.com/symbioticfi/core/blob/df9ca184c8ea82a887fc1922bce2558281ce8e60/src/interfaces/service/INetworkMiddlewareService.sol)


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

