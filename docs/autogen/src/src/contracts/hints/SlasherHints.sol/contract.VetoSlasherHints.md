# VetoSlasherHints
[Git Source](https://github.com/symbioticfi/core/blob/34733e78ecb0c08640f857df155aa6d467dd9462/src/contracts/hints/SlasherHints.sol)

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


### slashRequests

```solidity
IVetoSlasher.SlashRequest[] public slashRequests
```


### vetoDuration

```solidity
uint48 public vetoDuration
```


### resolverSetEpochsDelay

```solidity
uint256 public resolverSetEpochsDelay
```


### _resolver

```solidity
mapping(bytes32 subnetwork => Checkpoints.Trace208 value) internal _resolver
```


## Functions
### constructor


```solidity
constructor(address baseSlasherHints) ;
```

### resolverHintInternal


```solidity
function resolverHintInternal(bytes32 subnetwork, uint48 timestamp)
    external
    view
    internalFunction
    returns (bool exists, uint32 hint);
```

### resolverHint


```solidity
function resolverHint(address slasher, bytes32 subnetwork, uint48 timestamp)
    public
    view
    returns (bytes memory hint);
```

### requestSlashHints


```solidity
function requestSlashHints(address slasher, bytes32 subnetwork, address operator, uint48 captureTimestamp)
    external
    view
    returns (bytes memory hints);
```

### executeSlashHints


```solidity
function executeSlashHints(address slasher, uint256 slashIndex) external view returns (bytes memory hints);
```

### vetoSlashHints


```solidity
function vetoSlashHints(address slasher, uint256 slashIndex) external view returns (bytes memory hints);
```

### setResolverHints


```solidity
function setResolverHints(address slasher, bytes32 subnetwork, uint48 timestamp)
    external
    view
    returns (bytes memory hints);
```

