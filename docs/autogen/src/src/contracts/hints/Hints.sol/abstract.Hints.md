# Hints
[Git Source](https://github.com/symbioticfi/core/blob/5ab692fe7f696ff6aee61a77fae37dc444e1c86e/src/contracts/hints/Hints.sol)


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

