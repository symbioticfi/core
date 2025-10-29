# BaseSlasherHints
[Git Source](https://github.com/symbioticfi/core/blob/454f363c3e06eeffbe2515756b914d72c84b8ae4/src/contracts/hints/SlasherHints.sol)

**Inherits:**
[Hints](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/contracts/hints/Hints.sol/abstract.Hints.md)


## State Variables
### BASE_DELEGATOR_HINTS

```solidity
address public immutable BASE_DELEGATOR_HINTS
```


### SLASHER_HINTS

```solidity
address public immutable SLASHER_HINTS
```


### VETO_SLASHER_HINTS

```solidity
address public immutable VETO_SLASHER_HINTS
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
constructor(address baseDelegatorHints) ;
```

### cumulativeSlashHintInternal


```solidity
function cumulativeSlashHintInternal(bytes32 subnetwork, address operator, uint48 timestamp)
    external
    view
    internalFunction
    returns (bool exists, uint32 hint);
```

### cumulativeSlashHint


```solidity
function cumulativeSlashHint(address slasher, bytes32 subnetwork, address operator, uint48 timestamp)
    public
    view
    returns (bytes memory hint);
```

### slashableStakeHints


```solidity
function slashableStakeHints(address slasher, bytes32 subnetwork, address operator, uint48 captureTimestamp)
    external
    view
    returns (bytes memory hints);
```

