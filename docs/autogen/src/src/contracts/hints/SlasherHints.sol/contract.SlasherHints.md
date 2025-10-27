# SlasherHints
[Git Source](https://github.com/symbioticfi/core/blob/5ab692fe7f696ff6aee61a77fae37dc444e1c86e/src/contracts/hints/SlasherHints.sol)

**Inherits:**
[Hints](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/contracts/hints/Hints.sol/abstract.Hints.md)


## State Variables
### BASE_SLASHER_HINTS

```solidity
address public immutable BASE_SLASHER_HINTS
```


### vault

```solidity
address public vault
```


### isBurnerHook

```solidity
bool public isBurnerHook
```


### latestSlashedCaptureTimestamp

```solidity
mapping(bytes32 subnetwork => mapping(address operator => uint48 value)) public latestSlashedCaptureTimestamp
```


### _cumulativeSlash

```solidity
mapping(bytes32 subnetwork => mapping(address operator => Checkpoints.Trace256 amount)) internal _cumulativeSlash
```


## Functions
### constructor


```solidity
constructor(address baseSlasherHints) ;
```

### slashHints


```solidity
function slashHints(address slasher, bytes32 subnetwork, address operator, uint48 captureTimestamp)
    external
    view
    returns (bytes memory hints);
```

