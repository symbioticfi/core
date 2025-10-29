# VaultHints
[Git Source](https://github.com/symbioticfi/core/blob/f05307516bbf31fe6a8fa180eab4a8d7068a66a2/src/contracts/hints/VaultHints.sol)

**Inherits:**
[Hints](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/contracts/hints/Hints.sol/abstract.Hints.md)


## State Variables
### depositWhitelist

```solidity
bool public depositWhitelist
```


### isDepositLimit

```solidity
bool public isDepositLimit
```


### collateral

```solidity
address public collateral
```


### burner

```solidity
address public burner
```


### epochDurationInit

```solidity
uint48 public epochDurationInit
```


### epochDuration

```solidity
uint48 public epochDuration
```


### delegator

```solidity
address public delegator
```


### isDelegatorInitialized

```solidity
bool public isDelegatorInitialized
```


### slasher

```solidity
address public slasher
```


### isSlasherInitialized

```solidity
bool public isSlasherInitialized
```


### depositLimit

```solidity
uint256 public depositLimit
```


### isDepositorWhitelisted

```solidity
mapping(address account => bool value) public isDepositorWhitelisted
```


### withdrawals

```solidity
mapping(uint256 epoch => uint256 amount) public withdrawals
```


### withdrawalShares

```solidity
mapping(uint256 epoch => uint256 amount) public withdrawalShares
```


### withdrawalSharesOf

```solidity
mapping(uint256 epoch => mapping(address account => uint256 amount)) public withdrawalSharesOf
```


### isWithdrawalsClaimed

```solidity
mapping(uint256 epoch => mapping(address account => bool value)) public isWithdrawalsClaimed
```


### _activeShares

```solidity
Checkpoints.Trace256 internal _activeShares
```


### _activeStake

```solidity
Checkpoints.Trace256 internal _activeStake
```


### _activeSharesOf

```solidity
mapping(address account => Checkpoints.Trace256 shares) internal _activeSharesOf
```


## Functions
### constructor


```solidity
constructor() ;
```

### activeStakeHintInternal


```solidity
function activeStakeHintInternal(uint48 timestamp)
    external
    view
    internalFunction
    returns (bool exists, uint32 hint);
```

### activeStakeHint


```solidity
function activeStakeHint(address vault, uint48 timestamp) public view returns (bytes memory hint);
```

### activeSharesHintInternal


```solidity
function activeSharesHintInternal(uint48 timestamp)
    external
    view
    internalFunction
    returns (bool exists, uint32 hint);
```

### activeSharesHint


```solidity
function activeSharesHint(address vault, uint48 timestamp) public view returns (bytes memory hint);
```

### activeSharesOfHintInternal


```solidity
function activeSharesOfHintInternal(address account, uint48 timestamp)
    external
    view
    internalFunction
    returns (bool exists, uint32 hint);
```

### activeSharesOfHint


```solidity
function activeSharesOfHint(address vault, address account, uint48 timestamp)
    public
    view
    returns (bytes memory hint);
```

### activeBalanceOfHints


```solidity
function activeBalanceOfHints(address vault, address account, uint48 timestamp)
    external
    view
    returns (bytes memory hints);
```

