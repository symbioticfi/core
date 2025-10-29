# IMigratableEntityProxy
[Git Source](https://github.com/symbioticfi/core/blob/0515f07ba8e6512d27a7c84c3818ae0c899b4806/src/interfaces/common/IMigratableEntityProxy.sol)


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


