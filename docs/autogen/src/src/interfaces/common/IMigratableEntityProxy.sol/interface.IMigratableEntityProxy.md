# IMigratableEntityProxy
[Git Source](https://github.com/symbioticfi/core/blob/34733e78ecb0c08640f857df155aa6d467dd9462/src/interfaces/common/IMigratableEntityProxy.sol)


## Functions
### upgradeToAndCall

Upgrade the proxy to a new implementation and call a function on the new implementation.


```solidity
function upgradeToAndCall(address newImplementation, bytes calldata data) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newImplementation`|`address`|address of the new implementation|
|`data`|`bytes`|data to call on the new implementation|


