# NetworkRestakeDelegatorHints
[Git Source](https://github.com/symbioticfi/core/blob/454f363c3e06eeffbe2515756b914d72c84b8ae4/src/contracts/hints/DelegatorHints.sol)

**Inherits:**
[Hints](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/contracts/hints/Hints.sol/abstract.Hints.md)


## State Variables
### BASE_DELEGATOR_HINTS

```solidity
address public immutable BASE_DELEGATOR_HINTS
```


### VAULT_HINTS

```solidity
address public immutable VAULT_HINTS
```


### vault

```solidity
address public vault
```


### hook

```solidity
address public hook
```


### maxNetworkLimit

```solidity
mapping(bytes32 subnetwork => uint256 value) public maxNetworkLimit
```


### _networkLimit

```solidity
mapping(bytes32 subnetwork => Checkpoints.Trace256 value) internal _networkLimit
```


### _totalOperatorNetworkShares

```solidity
mapping(bytes32 subnetwork => Checkpoints.Trace256 shares) internal _totalOperatorNetworkShares
```


### _operatorNetworkShares

```solidity
mapping(bytes32 subnetwork => mapping(address operator => Checkpoints.Trace256 shares)) internal
    _operatorNetworkShares
```


## Functions
### constructor


```solidity
constructor(address baseDelegatorHints, address vaultHints) ;
```

### networkLimitHintInternal


```solidity
function networkLimitHintInternal(bytes32 subnetwork, uint48 timestamp)
    external
    view
    internalFunction
    returns (bool exists, uint32 hint);
```

### networkLimitHint


```solidity
function networkLimitHint(address delegator, bytes32 subnetwork, uint48 timestamp)
    public
    view
    returns (bytes memory hint);
```

### operatorNetworkSharesHintInternal


```solidity
function operatorNetworkSharesHintInternal(bytes32 subnetwork, address operator, uint48 timestamp)
    external
    view
    internalFunction
    returns (bool exists, uint32 hint);
```

### operatorNetworkSharesHint


```solidity
function operatorNetworkSharesHint(address delegator, bytes32 subnetwork, address operator, uint48 timestamp)
    public
    view
    returns (bytes memory hint);
```

### totalOperatorNetworkSharesHintInternal


```solidity
function totalOperatorNetworkSharesHintInternal(bytes32 subnetwork, uint48 timestamp)
    external
    view
    internalFunction
    returns (bool exists, uint32 hint);
```

### totalOperatorNetworkSharesHint


```solidity
function totalOperatorNetworkSharesHint(address delegator, bytes32 subnetwork, uint48 timestamp)
    public
    view
    returns (bytes memory hint);
```

### stakeHints


```solidity
function stakeHints(address delegator, bytes32 subnetwork, address operator, uint48 timestamp)
    external
    view
    returns (bytes memory hints);
```

