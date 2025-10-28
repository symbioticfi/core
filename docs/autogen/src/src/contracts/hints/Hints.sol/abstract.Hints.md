# Hints
[Git Source](https://github.com/symbioticfi/core/blob/45a7dbdd18fc5ac73ecf7310fc6816999bb8eef3/src/contracts/hints/Hints.sol)


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

