# Hints
[Git Source](https://github.com/symbioticfi/core/blob/0515f07ba8e6512d27a7c84c3818ae0c899b4806/src/contracts/hints/Hints.sol)


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

