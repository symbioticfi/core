# IMigratableEntityProxy
[Git Source](https://github.com/symbioticfi/core/blob/f05307516bbf31fe6a8fa180eab4a8d7068a66a2/src/interfaces/common/IMigratableEntityProxy.sol)


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


