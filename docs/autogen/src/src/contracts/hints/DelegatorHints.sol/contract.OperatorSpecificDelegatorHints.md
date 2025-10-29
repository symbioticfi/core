# OperatorSpecificDelegatorHints
[Git Source](https://github.com/symbioticfi/core/blob/0515f07ba8e6512d27a7c84c3818ae0c899b4806/src/contracts/hints/DelegatorHints.sol)

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


### operator

```solidity
address public operator
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

### stakeHints


```solidity
function stakeHints(address delegator, bytes32 subnetwork, address operator_, uint48 timestamp)
    external
    view
    returns (bytes memory hints);
```

