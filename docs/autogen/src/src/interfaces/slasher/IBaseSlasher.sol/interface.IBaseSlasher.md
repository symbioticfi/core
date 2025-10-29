# IBaseSlasher
[Git Source](https://github.com/symbioticfi/core/blob/f05307516bbf31fe6a8fa180eab4a8d7068a66a2/src/interfaces/slasher/IBaseSlasher.sol)

**Inherits:**
[IEntity](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/interfaces/common/IEntity.sol/interface.IEntity.md)


## Functions
### BURNER_GAS_LIMIT

Get a gas limit for the burner.


```solidity
function BURNER_GAS_LIMIT() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|value of the burner gas limit|


### BURNER_RESERVE

Get a reserve gas between the gas limit check and the burner's execution.


```solidity
function BURNER_RESERVE() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|value of the reserve gas|


### VAULT_FACTORY

Get the vault factory's address.


```solidity
function VAULT_FACTORY() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|address of the vault factory|


### NETWORK_MIDDLEWARE_SERVICE

Get the network middleware service's address.


```solidity
function NETWORK_MIDDLEWARE_SERVICE() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|address of the network middleware service|


### vault

Get the vault's address.


```solidity
function vault() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|address of the vault to perform slashings on|


### isBurnerHook

Get if the burner is needed to be called on a slashing.


```solidity
function isBurnerHook() external view returns (bool);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|if the burner is a hook|


### latestSlashedCaptureTimestamp

Get the latest capture timestamp that was slashed on a subnetwork.


```solidity
function latestSlashedCaptureTimestamp(bytes32 subnetwork, address operator) external view returns (uint48);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`subnetwork`|`bytes32`|full identifier of the subnetwork (address of the network concatenated with the uint96 identifier)|
|`operator`|`address`|address of the operator|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint48`|latest capture timestamp that was slashed|


### cumulativeSlashAt

Get a cumulative slash amount for an operator on a subnetwork until a given timestamp (inclusively) using a hint.


```solidity
function cumulativeSlashAt(bytes32 subnetwork, address operator, uint48 timestamp, bytes memory hint)
    external
    view
    returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`subnetwork`|`bytes32`|full identifier of the subnetwork (address of the network concatenated with the uint96 identifier)|
|`operator`|`address`|address of the operator|
|`timestamp`|`uint48`|time point to get the cumulative slash amount until (inclusively)|
|`hint`|`bytes`|hint for the checkpoint index|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|cumulative slash amount until the given timestamp (inclusively)|


### cumulativeSlash

Get a cumulative slash amount for an operator on a subnetwork.


```solidity
function cumulativeSlash(bytes32 subnetwork, address operator) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`subnetwork`|`bytes32`|full identifier of the subnetwork (address of the network concatenated with the uint96 identifier)|
|`operator`|`address`|address of the operator|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|cumulative slash amount|


### slashableStake

Get a slashable amount of a stake got at a given capture timestamp using hints.


```solidity
function slashableStake(bytes32 subnetwork, address operator, uint48 captureTimestamp, bytes memory hints)
    external
    view
    returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`subnetwork`|`bytes32`|full identifier of the subnetwork (address of the network concatenated with the uint96 identifier)|
|`operator`|`address`|address of the operator|
|`captureTimestamp`|`uint48`|time point to get the stake amount at|
|`hints`|`bytes`|hints for the checkpoints' indexes|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|slashable amount of the stake|


## Errors
### NoBurner

```solidity
error NoBurner();
```

### InsufficientBurnerGas

```solidity
error InsufficientBurnerGas();
```

### NotNetworkMiddleware

```solidity
error NotNetworkMiddleware();
```

### NotVault

```solidity
error NotVault();
```

## Structs
### BaseParams
Base parameters needed for slashers' deployment.


```solidity
struct BaseParams {
    bool isBurnerHook;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`isBurnerHook`|`bool`|if the burner is needed to be called on a slashing|

### SlashableStakeHints
Hints for a slashable stake.


```solidity
struct SlashableStakeHints {
    bytes stakeHints;
    bytes cumulativeSlashFromHint;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`stakeHints`|`bytes`|hints for the stake checkpoints|
|`cumulativeSlashFromHint`|`bytes`|hint for the cumulative slash amount at a capture timestamp|

### GeneralDelegatorData
General data for the delegator.


```solidity
struct GeneralDelegatorData {
    uint64 slasherType;
    bytes data;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`slasherType`|`uint64`|type of the slasher|
|`data`|`bytes`|slasher-dependent data for the delegator|

