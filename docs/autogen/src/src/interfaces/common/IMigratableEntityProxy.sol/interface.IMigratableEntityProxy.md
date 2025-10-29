# IMigratableEntityProxy
[Git Source](https://github.com/symbioticfi/core/blob/72d444d21da2b07516bb08def1e4b57d35cf27c3/src/interfaces/common/IMigratableEntityProxy.sol)


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


