# StaticDelegateCallable
[Git Source](https://github.com/symbioticfi/core/blob/72d444d21da2b07516bb08def1e4b57d35cf27c3/src/contracts/common/StaticDelegateCallable.sol)

**Inherits:**
[IStaticDelegateCallable](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/interfaces/common/IStaticDelegateCallable.sol/interface.IStaticDelegateCallable.md)


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


