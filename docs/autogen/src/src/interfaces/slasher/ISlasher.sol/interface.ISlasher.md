# ISlasher
[Git Source](https://github.com/symbioticfi/core/blob/34733e78ecb0c08640f857df155aa6d467dd9462/src/interfaces/slasher/ISlasher.sol)

**Inherits:**
[IBaseSlasher](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/interfaces/slasher/IBaseSlasher.sol/interface.IBaseSlasher.md)


## Functions
### slash

Perform a slash using a subnetwork for a particular operator by a given amount using hints.

Only a network middleware can call this function.


```solidity
function slash(bytes32 subnetwork, address operator, uint256 amount, uint48 captureTimestamp, bytes calldata hints)
    external
    returns (uint256 slashedAmount);
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
|`slashedAmount`|`uint256`|virtual amount of the collateral slashed|


## Events
### Slash
Emitted when a slash is performed.


```solidity
event Slash(bytes32 indexed subnetwork, address indexed operator, uint256 slashedAmount, uint48 captureTimestamp);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`subnetwork`|`bytes32`|subnetwork that requested the slash|
|`operator`|`address`|operator that is slashed|
|`slashedAmount`|`uint256`|virtual amount of the collateral slashed|
|`captureTimestamp`|`uint48`|time point when the stake was captured|

## Errors
### InsufficientSlash

```solidity
error InsufficientSlash();
```

### InvalidCaptureTimestamp

```solidity
error InvalidCaptureTimestamp();
```

## Structs
### InitParams
Initial parameters needed for a slasher deployment.


```solidity
struct InitParams {
    IBaseSlasher.BaseParams baseParams;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`baseParams`|`IBaseSlasher.BaseParams`|base parameters for slashers' deployment|

### SlashHints
Hints for a slash.


```solidity
struct SlashHints {
    bytes slashableStakeHints;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`slashableStakeHints`|`bytes`|hints for the slashable stake checkpoints|

### DelegatorData
Extra data for the delegator.


```solidity
struct DelegatorData {
    uint256 slashableStake;
    uint256 stakeAt;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`slashableStake`|`uint256`|amount of the slashable stake before the slash (cache)|
|`stakeAt`|`uint256`|amount of the stake at the capture time (cache)|

