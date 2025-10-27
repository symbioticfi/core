# IVaultStorage
[Git Source](https://github.com/symbioticfi/core/blob/4905f62919b30e0606fff3aaa7fcd52bf8ee3d3e/src/interfaces/vault/IVaultStorage.sol)


## Functions
### DEPOSIT_WHITELIST_SET_ROLE

Get a deposit whitelist enabler/disabler's role.


```solidity
function DEPOSIT_WHITELIST_SET_ROLE() external view returns (bytes32);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes32`|identifier of the whitelist enabler/disabler role|


### DEPOSITOR_WHITELIST_ROLE

Get a depositor whitelist status setter's role.


```solidity
function DEPOSITOR_WHITELIST_ROLE() external view returns (bytes32);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes32`|identifier of the depositor whitelist status setter role|


### IS_DEPOSIT_LIMIT_SET_ROLE

Get a deposit limit enabler/disabler's role.


```solidity
function IS_DEPOSIT_LIMIT_SET_ROLE() external view returns (bytes32);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes32`|identifier of the deposit limit enabler/disabler role|


### DEPOSIT_LIMIT_SET_ROLE

Get a deposit limit setter's role.


```solidity
function DEPOSIT_LIMIT_SET_ROLE() external view returns (bytes32);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes32`|identifier of the deposit limit setter role|


### DELEGATOR_FACTORY

Get the delegator factory's address.


```solidity
function DELEGATOR_FACTORY() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|address of the delegator factory|


### SLASHER_FACTORY

Get the slasher factory's address.


```solidity
function SLASHER_FACTORY() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|address of the slasher factory|


### collateral

Get a vault collateral.


```solidity
function collateral() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|address of the underlying collateral|


### burner

Get a burner to issue debt to (e.g., 0xdEaD or some unwrapper contract).


```solidity
function burner() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|address of the burner|


### delegator

Get a delegator (it delegates the vault's stake to networks and operators).


```solidity
function delegator() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|address of the delegator|


### isDelegatorInitialized

Get if the delegator is initialized.


```solidity
function isDelegatorInitialized() external view returns (bool);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|if the delegator is initialized|


### slasher

Get a slasher (it provides networks a slashing mechanism).


```solidity
function slasher() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|address of the slasher|


### isSlasherInitialized

Get if the slasher is initialized.


```solidity
function isSlasherInitialized() external view returns (bool);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|if the slasher is initialized|


### epochDurationInit

Get a time point of the epoch duration set.


```solidity
function epochDurationInit() external view returns (uint48);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint48`|time point of the epoch duration set|


### epochDuration

Get a duration of the vault epoch.


```solidity
function epochDuration() external view returns (uint48);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint48`|duration of the epoch|


### epochAt

Get an epoch at a given timestamp.

Reverts if the timestamp is less than the start of the epoch 0.


```solidity
function epochAt(uint48 timestamp) external view returns (uint256);
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
function currentEpoch() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|current epoch|


### currentEpochStart

Get a start of the current vault epoch.


```solidity
function currentEpochStart() external view returns (uint48);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint48`|start of the current epoch|


### previousEpochStart

Get a start of the previous vault epoch.

Reverts if the current epoch is 0.


```solidity
function previousEpochStart() external view returns (uint48);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint48`|start of the previous epoch|


### nextEpochStart

Get a start of the next vault epoch.


```solidity
function nextEpochStart() external view returns (uint48);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint48`|start of the next epoch|


### depositWhitelist

Get if the deposit whitelist is enabled.


```solidity
function depositWhitelist() external view returns (bool);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|if the deposit whitelist is enabled|


### isDepositorWhitelisted

Get if a given account is whitelisted as a depositor.


```solidity
function isDepositorWhitelisted(address account) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|address to check|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|if the account is whitelisted as a depositor|


### isDepositLimit

Get if the deposit limit is set.


```solidity
function isDepositLimit() external view returns (bool);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|if the deposit limit is set|


### depositLimit

Get a deposit limit (maximum amount of the active stake that can be in the vault simultaneously).


```solidity
function depositLimit() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|deposit limit|


### activeSharesAt

Get a total number of active shares in the vault at a given timestamp using a hint.


```solidity
function activeSharesAt(uint48 timestamp, bytes memory hint) external view returns (uint256);
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
function activeShares() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|total number of active shares|


### activeStakeAt

Get a total amount of active stake in the vault at a given timestamp using a hint.


```solidity
function activeStakeAt(uint48 timestamp, bytes memory hint) external view returns (uint256);
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
function activeStake() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|total amount of active stake|


### activeSharesOfAt

Get a total number of active shares for a particular account at a given timestamp using a hint.


```solidity
function activeSharesOfAt(address account, uint48 timestamp, bytes memory hint) external view returns (uint256);
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
function activeSharesOf(address account) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|account to get the number of active shares for|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|number of active shares for the account|


### withdrawals

Get a total amount of the withdrawals at a given epoch.


```solidity
function withdrawals(uint256 epoch) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`epoch`|`uint256`|epoch to get the total amount of the withdrawals at|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|total amount of the withdrawals at the epoch|


### withdrawalShares

Get a total number of withdrawal shares at a given epoch.


```solidity
function withdrawalShares(uint256 epoch) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`epoch`|`uint256`|epoch to get the total number of withdrawal shares at|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|total number of withdrawal shares at the epoch|


### withdrawalSharesOf

Get a number of withdrawal shares for a particular account at a given epoch (zero if claimed).


```solidity
function withdrawalSharesOf(uint256 epoch, address account) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`epoch`|`uint256`|epoch to get the number of withdrawal shares for the account at|
|`account`|`address`|account to get the number of withdrawal shares for|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|number of withdrawal shares for the account at the epoch|


### isWithdrawalsClaimed

Get if the withdrawals are claimed for a particular account at a given epoch.


```solidity
function isWithdrawalsClaimed(uint256 epoch, address account) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`epoch`|`uint256`|epoch to check the withdrawals for the account at|
|`account`|`address`|account to check the withdrawals for|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|if the withdrawals are claimed for the account at the epoch|


## Errors
### InvalidTimestamp

```solidity
error InvalidTimestamp();
```

### NoPreviousEpoch

```solidity
error NoPreviousEpoch();
```

