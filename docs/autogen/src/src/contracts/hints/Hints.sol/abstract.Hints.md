# Hints
[Git Source](https://github.com/symbioticfi/core/blob/34733e78ecb0c08640f857df155aa6d467dd9462/src/contracts/hints/Hints.sol)


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

