# BaseDelegatorHints
[Git Source](https://github.com/symbioticfi/core/blob/72d444d21da2b07516bb08def1e4b57d35cf27c3/src/contracts/hints/DelegatorHints.sol)

**Inherits:**
[Hints](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/contracts/hints/Hints.sol/abstract.Hints.md)


## State Variables
### OPT_IN_SERVICE_HINTS

```solidity
address public immutable OPT_IN_SERVICE_HINTS
```


### NETWORK_RESTAKE_DELEGATOR_HINTS

```solidity
address public immutable NETWORK_RESTAKE_DELEGATOR_HINTS
```


### FULL_RESTAKE_DELEGATOR_HINTS

```solidity
address public immutable FULL_RESTAKE_DELEGATOR_HINTS
```


### OPERATOR_SPECIFIC_DELEGATOR_HINTS

```solidity
address public immutable OPERATOR_SPECIFIC_DELEGATOR_HINTS
```


### OPERATOR_NETWORK_SPECIFIC_DELEGATOR_HINTS

```solidity
address public immutable OPERATOR_NETWORK_SPECIFIC_DELEGATOR_HINTS
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


## Functions
### constructor


```solidity
constructor(address optInServiceHints, address vaultHints_) ;
```

### stakeHints


```solidity
function stakeHints(address delegator, bytes32 subnetwork, address operator, uint48 timestamp)
    public
    view
    returns (bytes memory hints);
```

### stakeBaseHints


```solidity
function stakeBaseHints(address delegator, bytes32 subnetwork, address operator, uint48 timestamp)
    external
    view
    returns (bytes memory baseHints);
```

