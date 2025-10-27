# VaultStorage
[Git Source](https://github.com/symbioticfi/core/blob/0c5792225777a2fa2f15f10dba9650eb44861800/src/contracts/vault/VaultStorage.sol)

**Inherits:**
[StaticDelegateCallable](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/contracts/common/StaticDelegateCallable.sol/abstract.StaticDelegateCallable.md), [IVaultStorage](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/interfaces/vault/IVaultStorage.sol/interface.IVaultStorage.md)


## State Variables
### DEPOSIT_WHITELIST_SET_ROLE
Get a deposit whitelist enabler/disabler's role.


```solidity
bytes32 public constant DEPOSIT_WHITELIST_SET_ROLE = keccak256("DEPOSIT_WHITELIST_SET_ROLE")
```


### DEPOSITOR_WHITELIST_ROLE
Get a depositor whitelist status setter's role.


```solidity
bytes32 public constant DEPOSITOR_WHITELIST_ROLE = keccak256("DEPOSITOR_WHITELIST_ROLE")
```


### IS_DEPOSIT_LIMIT_SET_ROLE
Get a deposit limit enabler/disabler's role.


```solidity
bytes32 public constant IS_DEPOSIT_LIMIT_SET_ROLE = keccak256("IS_DEPOSIT_LIMIT_SET_ROLE")
```


### DEPOSIT_LIMIT_SET_ROLE
Get a deposit limit setter's role.


```solidity
bytes32 public constant DEPOSIT_LIMIT_SET_ROLE = keccak256("DEPOSIT_LIMIT_SET_ROLE")
```


### DELEGATOR_FACTORY
Get the delegator factory's address.


```solidity
address public immutable DELEGATOR_FACTORY
```


### SLASHER_FACTORY
Get the slasher factory's address.


```solidity
address public immutable SLASHER_FACTORY
```


### depositWhitelist
Get if the deposit whitelist is enabled.


```solidity
bool public depositWhitelist
```


### isDepositLimit
Get if the deposit limit is set.


```solidity
bool public isDepositLimit
```


### collateral
Get a vault collateral.


```solidity
address public collateral
```


### burner
Get a burner to issue debt to (e.g., 0xdEaD or some unwrapper contract).


```solidity
address public burner
```


### epochDurationInit
Get a time point of the epoch duration set.


```solidity
uint48 public epochDurationInit
```


### epochDuration
Get a duration of the vault epoch.


```solidity
uint48 public epochDuration
```


### delegator
Get a delegator (it delegates the vault's stake to networks and operators).


```solidity
address public delegator
```


### isDelegatorInitialized
Get if the delegator is initialized.


```solidity
bool public isDelegatorInitialized
```


### slasher
Get a slasher (it provides networks a slashing mechanism).


```solidity
address public slasher
```


### isSlasherInitialized
Get if the slasher is initialized.


```solidity
bool public isSlasherInitialized
```


### depositLimit
Get a deposit limit (maximum amount of the active stake that can be in the vault simultaneously).


```solidity
uint256 public depositLimit
```


### isDepositorWhitelisted
Get if a given account is whitelisted as a depositor.


```solidity
mapping(address account => bool value) public isDepositorWhitelisted
```


### withdrawals
Get a total amount of the withdrawals at a given epoch.


```solidity
mapping(uint256 epoch => uint256 amount) public withdrawals
```


### withdrawalShares
Get a total number of withdrawal shares at a given epoch.


```solidity
mapping(uint256 epoch => uint256 amount) public withdrawalShares
```


### withdrawalSharesOf
Get a number of withdrawal shares for a particular account at a given epoch (zero if claimed).


```solidity
mapping(uint256 epoch => mapping(address account => uint256 amount)) public withdrawalSharesOf
```


### isWithdrawalsClaimed
Get if the withdrawals are claimed for a particular account at a given epoch.


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


### __gap

```solidity
uint256[50] private __gap
```


## Functions
### constructor


```solidity
constructor(address delegatorFactory, address slasherFactory) ;
```

### epochAt

Get an epoch at a given timestamp.

Reverts if the timestamp is less than the start of the epoch 0.


```solidity
function epochAt(uint48 timestamp) public view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`timestamp`|`uint48`|time point to get the epoch at|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|epoch at the timestamp|


### currentEpoch

Get a current vault epoch.


```solidity
function currentEpoch() public view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|current epoch|


### currentEpochStart

Get a start of the current vault epoch.


```solidity
function currentEpochStart() public view returns (uint48);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint48`|start of the current epoch|


### previousEpochStart

Get a start of the previous vault epoch.

Reverts if the current epoch is 0.


```solidity
function previousEpochStart() public view returns (uint48);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint48`|start of the previous epoch|


### nextEpochStart

Get a start of the next vault epoch.


```solidity
function nextEpochStart() public view returns (uint48);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint48`|start of the next epoch|


### activeSharesAt

Get a total number of active shares in the vault at a given timestamp using a hint.


```solidity
function activeSharesAt(uint48 timestamp, bytes memory hint) public view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`timestamp`|`uint48`|time point to get the total number of active shares at|
|`hint`|`bytes`|hint for the checkpoint index|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|total number of active shares at the timestamp|


### activeShares

Get a total number of active shares in the vault.


```solidity
function activeShares() public view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|total number of active shares|


### activeStakeAt

Get a total amount of active stake in the vault at a given timestamp using a hint.


```solidity
function activeStakeAt(uint48 timestamp, bytes memory hint) public view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`timestamp`|`uint48`|time point to get the total active stake at|
|`hint`|`bytes`|hint for the checkpoint index|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|total amount of active stake at the timestamp|


### activeStake

Get a total amount of active stake in the vault.


```solidity
function activeStake() public view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|total amount of active stake|


### activeSharesOfAt

Get a total number of active shares for a particular account at a given timestamp using a hint.


```solidity
function activeSharesOfAt(address account, uint48 timestamp, bytes memory hint) public view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|account to get the number of active shares for|
|`timestamp`|`uint48`|time point to get the number of active shares for the account at|
|`hint`|`bytes`|hint for the checkpoint index|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|number of active shares for the account at the timestamp|


### activeSharesOf

Get a number of active shares for a particular account.


```solidity
function activeSharesOf(address account) public view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|account to get the number of active shares for|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|number of active shares for the account|


