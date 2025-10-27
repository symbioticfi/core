# IStaticDelegateCallable
[Git Source](https://github.com/symbioticfi/core/blob/5ab692fe7f696ff6aee61a77fae37dc444e1c86e/src/interfaces/common/IStaticDelegateCallable.sol)


## Functions
### staticDelegateCall

Make a delegatecall from this contract to a given target contract with a particular data (always reverts with a return data).

It allows to use this contract's storage on-chain.


```solidity
function staticDelegateCall(address target, bytes calldata data) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`target`|`address`|address of the contract to make a delegatecall to|
|`data`|`bytes`|data to make a delegatecall with|


