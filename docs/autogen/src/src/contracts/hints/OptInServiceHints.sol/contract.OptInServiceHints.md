# OptInServiceHints
[Git Source](https://github.com/symbioticfi/core/blob/5ab692fe7f696ff6aee61a77fae37dc444e1c86e/src/contracts/hints/OptInServiceHints.sol)

**Inherits:**
[Hints](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/contracts/hints/Hints.sol/abstract.Hints.md)


## State Variables
### nonces

```solidity
mapping(address who => mapping(address where => uint256 nonce)) public nonces
```


### _isOptedIn

```solidity
mapping(address who => mapping(address where => Checkpoints.Trace208 value)) internal _isOptedIn
```


## Functions
### optInHintInternal


```solidity
function optInHintInternal(address who, address where, uint48 timestamp)
    external
    view
    internalFunction
    returns (bool exists, uint32 hint);
```

### optInHint


```solidity
function optInHint(address optInService, address who, address where, uint48 timestamp)
    external
    view
    returns (bytes memory hint);
```

