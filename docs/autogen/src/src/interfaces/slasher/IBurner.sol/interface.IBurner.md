# IBurner
[Git Source](https://github.com/symbioticfi/core/blob/5ab692fe7f696ff6aee61a77fae37dc444e1c86e/src/interfaces/slasher/IBurner.sol)


## Functions
### onSlash

Called when a slash happens.


```solidity
function onSlash(bytes32 subnetwork, address operator, uint256 amount, uint48 captureTimestamp) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`subnetwork`|`bytes32`|full identifier of the subnetwork (address of the network concatenated with the uint96 identifier)|
|`operator`|`address`|address of the operator|
|`amount`|`uint256`|virtual amount of the collateral slashed|
|`captureTimestamp`|`uint48`|time point when the stake was captured|


