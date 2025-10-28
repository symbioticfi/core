# IOptInService
[Git Source](https://github.com/symbioticfi/core/blob/45a7dbdd18fc5ac73ecf7310fc6816999bb8eef3/src/interfaces/service/IOptInService.sol)


## Functions
### WHO_REGISTRY

Get the "who" registry's address.


```solidity
function WHO_REGISTRY() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|address of the "who" registry|


### WHERE_REGISTRY

Get the address of the registry where to opt-in.


```solidity
function WHERE_REGISTRY() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|address of the "where" registry|


### isOptedInAt

Get if a given "who" is opted-in to a particular "where" entity at a given timestamp using a hint.


```solidity
function isOptedInAt(address who, address where, uint48 timestamp, bytes calldata hint) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`who`|`address`|address of the "who"|
|`where`|`address`|address of the "where" entity|
|`timestamp`|`uint48`|time point to get if the "who" is opted-in at|
|`hint`|`bytes`|hint for the checkpoint index|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|if the "who" is opted-in at the given timestamp|


### isOptedIn

Check if a given "who" is opted-in to a particular "where" entity.


```solidity
function isOptedIn(address who, address where) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`who`|`address`|address of the "who"|
|`where`|`address`|address of the "where" entity|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|if the "who" is opted-in|


### nonces

Get the nonce of a given "who" to a particular "where" entity.


```solidity
function nonces(address who, address where) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`who`|`address`|address of the "who"|
|`where`|`address`|address of the "where" entity|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|nonce|


### optIn

Opt-in a calling "who" to a particular "where" entity.


```solidity
function optIn(address where) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`where`|`address`|address of the "where" entity|


### optIn

Opt-in a "who" to a particular "where" entity with a signature.


```solidity
function optIn(address who, address where, uint48 deadline, bytes calldata signature) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`who`|`address`|address of the "who"|
|`where`|`address`|address of the "where" entity|
|`deadline`|`uint48`|time point until the signature is valid (inclusively)|
|`signature`|`bytes`|signature of the "who"|


### optOut

Opt-out a calling "who" from a particular "where" entity.


```solidity
function optOut(address where) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`where`|`address`|address of the "where" entity|


### optOut

Opt-out a "who" from a particular "where" entity with a signature.


```solidity
function optOut(address who, address where, uint48 deadline, bytes calldata signature) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`who`|`address`|address of the "who"|
|`where`|`address`|address of the "where" entity|
|`deadline`|`uint48`|time point until the signature is valid (inclusively)|
|`signature`|`bytes`|signature of the "who"|


### increaseNonce

Increase the nonce of a given "who" to a particular "where" entity.

It can be used to invalidate a given signature.


```solidity
function increaseNonce(address where) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`where`|`address`|address of the "where" entity|


## Events
### OptIn
Emitted when a "who" opts into a "where" entity.


```solidity
event OptIn(address indexed who, address indexed where);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`who`|`address`|address of the "who"|
|`where`|`address`|address of the "where" entity|

### OptOut
Emitted when a "who" opts out from a "where" entity.


```solidity
event OptOut(address indexed who, address indexed where);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`who`|`address`|address of the "who"|
|`where`|`address`|address of the "where" entity|

### IncreaseNonce
Emitted when the nonce of a "who" to a "where" entity is increased.


```solidity
event IncreaseNonce(address indexed who, address indexed where);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`who`|`address`|address of the "who"|
|`where`|`address`|address of the "where" entity|

## Errors
### AlreadyOptedIn

```solidity
error AlreadyOptedIn();
```

### ExpiredSignature

```solidity
error ExpiredSignature();
```

### InvalidSignature

```solidity
error InvalidSignature();
```

### NotOptedIn

```solidity
error NotOptedIn();
```

### NotWhereEntity

```solidity
error NotWhereEntity();
```

### NotWho

```solidity
error NotWho();
```

### OptOutCooldown

```solidity
error OptOutCooldown();
```

