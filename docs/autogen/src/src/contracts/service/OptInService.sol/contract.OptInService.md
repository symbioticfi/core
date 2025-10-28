# OptInService
[Git Source](https://github.com/symbioticfi/core/blob/45a7dbdd18fc5ac73ecf7310fc6816999bb8eef3/src/contracts/service/OptInService.sol)

**Inherits:**
[StaticDelegateCallable](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/contracts/common/StaticDelegateCallable.sol/abstract.StaticDelegateCallable.md), EIP712, [IOptInService](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/interfaces/service/IOptInService.sol/interface.IOptInService.md)


## State Variables
### WHO_REGISTRY
Get the "who" registry's address.


```solidity
address public immutable WHO_REGISTRY
```


### WHERE_REGISTRY
Get the address of the registry where to opt-in.


```solidity
address public immutable WHERE_REGISTRY
```


### OPT_IN_TYPEHASH

```solidity
bytes32 private constant OPT_IN_TYPEHASH =
    keccak256("OptIn(address who,address where,uint256 nonce,uint48 deadline)")
```


### OPT_OUT_TYPEHASH

```solidity
bytes32 private constant OPT_OUT_TYPEHASH =
    keccak256("OptOut(address who,address where,uint256 nonce,uint48 deadline)")
```


### nonces
Get the nonce of a given "who" to a particular "where" entity.


```solidity
mapping(address who => mapping(address where => uint256 nonce)) public nonces
```


### _isOptedIn

```solidity
mapping(address who => mapping(address where => Checkpoints.Trace208 value)) internal _isOptedIn
```


## Functions
### checkDeadline


```solidity
modifier checkDeadline(uint48 deadline) ;
```

### constructor


```solidity
constructor(address whoRegistry, address whereRegistry, string memory name) EIP712(name, "1");
```

### isOptedInAt

Get if a given "who" is opted-in to a particular "where" entity at a given timestamp using a hint.


```solidity
function isOptedInAt(address who, address where, uint48 timestamp, bytes calldata hint)
    external
    view
    returns (bool);
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
function isOptedIn(address who, address where) public view returns (bool);
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

Opt-in a calling "who" to a particular "where" entity.


```solidity
function optIn(address who, address where, uint48 deadline, bytes calldata signature)
    external
    checkDeadline(deadline);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`who`|`address`||
|`where`|`address`|address of the "where" entity|
|`deadline`|`uint48`||
|`signature`|`bytes`||


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

Opt-out a calling "who" from a particular "where" entity.


```solidity
function optOut(address who, address where, uint48 deadline, bytes calldata signature)
    external
    checkDeadline(deadline);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`who`|`address`||
|`where`|`address`|address of the "where" entity|
|`deadline`|`uint48`||
|`signature`|`bytes`||


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


### _optIn


```solidity
function _optIn(address who, address where) internal;
```

### _optOut


```solidity
function _optOut(address who, address where) internal;
```

### _hash


```solidity
function _hash(bool ifOptIn, address who, address where, uint48 deadline) internal view returns (bytes32);
```

### _increaseNonce


```solidity
function _increaseNonce(address who, address where) internal;
```

