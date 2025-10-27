# IVetoSlasher
[Git Source](https://github.com/symbioticfi/core/blob/df9ca184c8ea82a887fc1922bce2558281ce8e60/src/interfaces/slasher/IVetoSlasher.sol)

**Inherits:**
[IBaseSlasher](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/interfaces/slasher/IBaseSlasher.sol/interface.IBaseSlasher.md)


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


### vetoDuration

Get a duration during which resolvers can veto slash requests.


```solidity
function vetoDuration() external view returns (uint48);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint48`|duration of the veto period|


### slashRequestsLength

Get a total number of slash requests.


```solidity
function slashRequestsLength() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|total number of slash requests|


### slashRequests

Get a particular slash request.


```solidity
function slashRequests(uint256 slashIndex)
    external
    view
    returns (
        bytes32 subnetwork,
        address operator,
        uint256 amount,
        uint48 captureTimestamp,
        uint48 vetoDeadline,
        bool completed
    );
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`slashIndex`|`uint256`|index of the slash request|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`subnetwork`|`bytes32`|subnetwork that requested the slash|
|`operator`|`address`|operator that could be slashed (if the request is not vetoed)|
|`amount`|`uint256`|maximum amount of the collateral to be slashed|
|`captureTimestamp`|`uint48`|time point when the stake was captured|
|`vetoDeadline`|`uint48`|deadline for the resolver to veto the slash (exclusively)|
|`completed`|`bool`|if the slash was vetoed/executed|


### resolverSetEpochsDelay

Get a delay for networks in epochs to update a resolver.


```solidity
function resolverSetEpochsDelay() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|updating resolver delay in epochs|


### resolverAt

Get a resolver for a given subnetwork at a particular timestamp using a hint.


```solidity
function resolverAt(bytes32 subnetwork, uint48 timestamp, bytes memory hint) external view returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`subnetwork`|`bytes32`|full identifier of the subnetwork (address of the network concatenated with the uint96 identifier)|
|`timestamp`|`uint48`|timestamp to get the resolver at|
|`hint`|`bytes`|hint for the checkpoint index|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|address of the resolver|


### resolver

Get a resolver for a given subnetwork using a hint.


```solidity
function resolver(bytes32 subnetwork, bytes memory hint) external view returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`subnetwork`|`bytes32`|full identifier of the subnetwork (address of the network concatenated with the uint96 identifier)|
|`hint`|`bytes`|hint for the checkpoint index|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|address of the resolver|


### requestSlash

Request a slash using a subnetwork for a particular operator by a given amount using hints.

Only a network middleware can call this function.


```solidity
function requestSlash(
    bytes32 subnetwork,
    address operator,
    uint256 amount,
    uint48 captureTimestamp,
    bytes calldata hints
) external returns (uint256 slashIndex);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`subnetwork`|`bytes32`|full identifier of the subnetwork (address of the network concatenated with the uint96 identifier)|
|`operator`|`address`|address of the operator|
|`amount`|`uint256`|maximum amount of the collateral to be slashed|
|`captureTimestamp`|`uint48`|time point when the stake was captured|
|`hints`|`bytes`|hints for checkpoints' indexes|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`slashIndex`|`uint256`|index of the slash request|


### executeSlash

Execute a slash with a given slash index using hints.

Only a network middleware can call this function.


```solidity
function executeSlash(uint256 slashIndex, bytes calldata hints) external returns (uint256 slashedAmount);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`slashIndex`|`uint256`|index of the slash request|
|`hints`|`bytes`|hints for checkpoints' indexes|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`slashedAmount`|`uint256`|virtual amount of the collateral slashed|


### vetoSlash

Veto a slash with a given slash index using hints.

Only a resolver can call this function.


```solidity
function vetoSlash(uint256 slashIndex, bytes calldata hints) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`slashIndex`|`uint256`|index of the slash request|
|`hints`|`bytes`|hints for checkpoints' indexes|


### setResolver

Set a resolver for a subnetwork using hints.
identifier identifier of the subnetwork

Only a network can call this function.


```solidity
function setResolver(uint96 identifier, address resolver, bytes calldata hints) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`identifier`|`uint96`||
|`resolver`|`address`|address of the resolver|
|`hints`|`bytes`|hints for checkpoints' indexes|


## Events
### RequestSlash
Emitted when a slash request is created.


```solidity
event RequestSlash(
    uint256 indexed slashIndex,
    bytes32 indexed subnetwork,
    address indexed operator,
    uint256 slashAmount,
    uint48 captureTimestamp,
    uint48 vetoDeadline
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`slashIndex`|`uint256`|index of the slash request|
|`subnetwork`|`bytes32`|subnetwork that requested the slash|
|`operator`|`address`|operator that could be slashed (if the request is not vetoed)|
|`slashAmount`|`uint256`|maximum amount of the collateral to be slashed|
|`captureTimestamp`|`uint48`|time point when the stake was captured|
|`vetoDeadline`|`uint48`|deadline for the resolver to veto the slash (exclusively)|

### ExecuteSlash
Emitted when a slash request is executed.


```solidity
event ExecuteSlash(uint256 indexed slashIndex, uint256 slashedAmount);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`slashIndex`|`uint256`|index of the slash request|
|`slashedAmount`|`uint256`|virtual amount of the collateral slashed|

### VetoSlash
Emitted when a slash request is vetoed.


```solidity
event VetoSlash(uint256 indexed slashIndex, address indexed resolver);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`slashIndex`|`uint256`|index of the slash request|
|`resolver`|`address`|address of the resolver that vetoed the slash|

### SetResolver
Emitted when a resolver is set.


```solidity
event SetResolver(bytes32 indexed subnetwork, address resolver);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`subnetwork`|`bytes32`|full identifier of the subnetwork (address of the network concatenated with the uint96 identifier)|
|`resolver`|`address`|address of the resolver|

## Errors
### AlreadySet

```solidity
error AlreadySet();
```

### InsufficientSlash

```solidity
error InsufficientSlash();
```

### InvalidCaptureTimestamp

```solidity
error InvalidCaptureTimestamp();
```

### InvalidResolverSetEpochsDelay

```solidity
error InvalidResolverSetEpochsDelay();
```

### InvalidVetoDuration

```solidity
error InvalidVetoDuration();
```

### NoResolver

```solidity
error NoResolver();
```

### NotNetwork

```solidity
error NotNetwork();
```

### NotResolver

```solidity
error NotResolver();
```

### SlashPeriodEnded

```solidity
error SlashPeriodEnded();
```

### SlashRequestCompleted

```solidity
error SlashRequestCompleted();
```

### SlashRequestNotExist

```solidity
error SlashRequestNotExist();
```

### VetoPeriodEnded

```solidity
error VetoPeriodEnded();
```

### VetoPeriodNotEnded

```solidity
error VetoPeriodNotEnded();
```

## Structs
### InitParams
Initial parameters needed for a slasher deployment.


```solidity
struct InitParams {
    IBaseSlasher.BaseParams baseParams;
    uint48 vetoDuration;
    uint256 resolverSetEpochsDelay;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`baseParams`|`IBaseSlasher.BaseParams`|base parameters for slashers' deployment|
|`vetoDuration`|`uint48`|duration of the veto period for a slash request|
|`resolverSetEpochsDelay`|`uint256`|delay in epochs for a network to update a resolver|

### SlashRequest
Structure for a slash request.


```solidity
struct SlashRequest {
    bytes32 subnetwork;
    address operator;
    uint256 amount;
    uint48 captureTimestamp;
    uint48 vetoDeadline;
    bool completed;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`subnetwork`|`bytes32`|subnetwork that requested the slash|
|`operator`|`address`|operator that could be slashed (if the request is not vetoed)|
|`amount`|`uint256`|maximum amount of the collateral to be slashed|
|`captureTimestamp`|`uint48`|time point when the stake was captured|
|`vetoDeadline`|`uint48`|deadline for the resolver to veto the slash (exclusively)|
|`completed`|`bool`|if the slash was vetoed/executed|

### RequestSlashHints
Hints for a slash request.


```solidity
struct RequestSlashHints {
    bytes slashableStakeHints;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`slashableStakeHints`|`bytes`|hints for the slashable stake checkpoints|

### ExecuteSlashHints
Hints for a slash execute.


```solidity
struct ExecuteSlashHints {
    bytes captureResolverHint;
    bytes currentResolverHint;
    bytes slashableStakeHints;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`captureResolverHint`|`bytes`|hint for the resolver checkpoint at the capture time|
|`currentResolverHint`|`bytes`|hint for the resolver checkpoint at the current time|
|`slashableStakeHints`|`bytes`|hints for the slashable stake checkpoints|

### VetoSlashHints
Hints for a slash veto.


```solidity
struct VetoSlashHints {
    bytes captureResolverHint;
    bytes currentResolverHint;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`captureResolverHint`|`bytes`|hint for the resolver checkpoint at the capture time|
|`currentResolverHint`|`bytes`|hint for the resolver checkpoint at the current time|

### SetResolverHints
Hints for a resolver set.


```solidity
struct SetResolverHints {
    bytes resolverHint;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`resolverHint`|`bytes`|hint for the resolver checkpoint|

### DelegatorData
Extra data for the delegator.


```solidity
struct DelegatorData {
    uint256 slashableStake;
    uint256 stakeAt;
    uint256 slashIndex;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`slashableStake`|`uint256`|amount of the slashable stake before the slash (cache)|
|`stakeAt`|`uint256`|amount of the stake at the capture time (cache)|
|`slashIndex`|`uint256`|index of the slash request|

