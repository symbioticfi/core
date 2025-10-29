# VetoSlasher
[Git Source](https://github.com/symbioticfi/core/blob/0515f07ba8e6512d27a7c84c3818ae0c899b4806/src/contracts/slasher/VetoSlasher.sol)

**Inherits:**
[BaseSlasher](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/contracts/slasher/BaseSlasher.sol/abstract.BaseSlasher.md), [IVetoSlasher](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/interfaces/slasher/IVetoSlasher.sol/interface.IVetoSlasher.md)


## State Variables
### NETWORK_REGISTRY
Get the network registry's address.


```solidity
address public immutable NETWORK_REGISTRY
```


### slashRequests
Get a particular slash request.


```solidity
SlashRequest[] public slashRequests
```


### vetoDuration
Get a duration during which resolvers can veto slash requests.


```solidity
uint48 public vetoDuration
```


### resolverSetEpochsDelay
Get a delay for networks in epochs to update a resolver.


```solidity
uint256 public resolverSetEpochsDelay
```


### _resolver

```solidity
mapping(bytes32 subnetwork => Checkpoints.Trace208 value) internal _resolver
```


## Functions
### constructor


```solidity
constructor(
    address vaultFactory,
    address networkMiddlewareService,
    address networkRegistry,
    address slasherFactory,
    uint64 entityType
) BaseSlasher(vaultFactory, networkMiddlewareService, slasherFactory, entityType);
```

### slashRequestsLength

Get a total number of slash requests.


```solidity
function slashRequestsLength() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|total number of slash requests|


### resolverAt

Get a resolver for a given subnetwork at a particular timestamp using a hint.


```solidity
function resolverAt(bytes32 subnetwork, uint48 timestamp, bytes memory hint) public view returns (address);
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
function resolver(bytes32 subnetwork, bytes memory hint) public view returns (address);
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
) external nonReentrant onlyNetworkMiddleware(subnetwork) returns (uint256 slashIndex);
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
function executeSlash(uint256 slashIndex, bytes calldata hints)
    external
    nonReentrant
    returns (uint256 slashedAmount);
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
function vetoSlash(uint256 slashIndex, bytes calldata hints) external nonReentrant;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`slashIndex`|`uint256`|index of the slash request|
|`hints`|`bytes`|hints for checkpoints' indexes|


### setResolver


```solidity
function setResolver(uint96 identifier, address resolver_, bytes calldata hints) external nonReentrant;
```

### __initialize


```solidity
function __initialize(address vault_, bytes memory data) internal override returns (BaseParams memory);
```

