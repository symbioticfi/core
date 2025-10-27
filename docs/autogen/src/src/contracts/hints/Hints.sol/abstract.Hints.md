# Hints
[Git Source](https://github.com/symbioticfi/core/blob/0c5792225777a2fa2f15f10dba9650eb44861800/src/contracts/hints/Hints.sol)


## State Variables
### _SELF

```solidity
address private immutable _SELF
```


## Functions
### constructor


```solidity
constructor() ;
```

### internalFunction


```solidity
modifier internalFunction() ;
```

### _selfStaticDelegateCall


```solidity
function _selfStaticDelegateCall(address target, bytes memory dataInternal) internal view returns (bytes memory);
```

## Errors
### ExternalCall

```solidity
error ExternalCall();
```

