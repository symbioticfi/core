# IBaseDelegator
[Git Source](https://github.com/symbioticfi/core/blob/0515f07ba8e6512d27a7c84c3818ae0c899b4806/src/interfaces/delegator/IBaseDelegator.sol)

**Inherits:**
[IEntity](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/interfaces/common/IEntity.sol/interface.IEntity.md)


## Functions
### VERSION

Get a version of the delegator (different versions mean different interfaces).

Must return 1 for this one.


```solidity
function VERSION() external view returns (uint64);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint64`|version of the delegator|


### NETWORK_REGISTRY

Get the network registry's address.


```solidity
function NETWORK_REGISTRY() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|address of the network registry|


### VAULT_FACTORY

Get the vault factory's address.


```solidity
function VAULT_FACTORY() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|address of the vault factory|


### OPERATOR_VAULT_OPT_IN_SERVICE

Get the operator-vault opt-in service's address.


```solidity
function OPERATOR_VAULT_OPT_IN_SERVICE() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|address of the operator-vault opt-in service|


### OPERATOR_NETWORK_OPT_IN_SERVICE

Get the operator-network opt-in service's address.


```solidity
function OPERATOR_NETWORK_OPT_IN_SERVICE() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|address of the operator-network opt-in service|


### HOOK_GAS_LIMIT

Get a gas limit for the hook.


```solidity
function HOOK_GAS_LIMIT() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|value of the hook gas limit|


### HOOK_RESERVE

Get a reserve gas between the gas limit check and the hook's execution.


```solidity
function HOOK_RESERVE() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|value of the reserve gas|


### HOOK_SET_ROLE

Get a hook setter's role.


```solidity
function HOOK_SET_ROLE() external view returns (bytes32);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes32`|identifier of the hook setter role|


### vault

Get the vault's address.


```solidity
function vault() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|address of the vault|


### hook

Get the hook's address.

The hook can have arbitrary logic under certain functions, however, it doesn't affect the stake guarantees.


```solidity
function hook() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|address of the hook|


### maxNetworkLimit

Get a particular subnetwork's maximum limit
(meaning the subnetwork is not ready to get more as a stake).


```solidity
function maxNetworkLimit(bytes32 subnetwork) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`subnetwork`|`bytes32`|full identifier of the subnetwork (address of the network concatenated with the uint96 identifier)|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|maximum limit of the subnetwork|


### stakeAt

Get a stake that a given subnetwork could be able to slash for a certain operator at a given timestamp
until the end of the consequent epoch using hints (if no cross-slashing and no slashings by the subnetwork).

Warning: it is not safe to use timestamp >= current one for the stake capturing, as it can change later.


```solidity
function stakeAt(bytes32 subnetwork, address operator, uint48 timestamp, bytes memory hints)
    external
    view
    returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`subnetwork`|`bytes32`|full identifier of the subnetwork (address of the network concatenated with the uint96 identifier)|
|`operator`|`address`|address of the operator|
|`timestamp`|`uint48`|time point to capture the stake at|
|`hints`|`bytes`|hints for the checkpoints' indexes|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|slashable stake at the given timestamp until the end of the consequent epoch|


### stake

Get a stake that a given subnetwork will be able to slash
for a certain operator until the end of the next epoch (if no cross-slashing and no slashings by the subnetwork).

Warning: this function is not safe to use for stake capturing, as it can change by the end of the block.


```solidity
function stake(bytes32 subnetwork, address operator) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`subnetwork`|`bytes32`|full identifier of the subnetwork (address of the network concatenated with the uint96 identifier)|
|`operator`|`address`|address of the operator|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|slashable stake until the end of the next epoch|


### setMaxNetworkLimit

Set a maximum limit for a subnetwork (how much stake the subnetwork is ready to get).
identifier identifier of the subnetwork

Only a network can call this function.


```solidity
function setMaxNetworkLimit(uint96 identifier, uint256 amount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`identifier`|`uint96`||
|`amount`|`uint256`|new maximum subnetwork's limit|


### setHook

Set a new hook.

Only a HOOK_SET_ROLE holder can call this function.
The hook can have arbitrary logic under certain functions, however, it doesn't affect the stake guarantees.


```solidity
function setHook(address hook) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`hook`|`address`|address of the hook|


### onSlash

Called when a slash happens.

Only the vault's slasher can call this function.


```solidity
function onSlash(
    bytes32 subnetwork,
    address operator,
    uint256 amount,
    uint48 captureTimestamp,
    bytes calldata data
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`subnetwork`|`bytes32`|full identifier of the subnetwork (address of the network concatenated with the uint96 identifier)|
|`operator`|`address`|address of the operator|
|`amount`|`uint256`|amount of the collateral slashed|
|`captureTimestamp`|`uint48`|time point when the stake was captured|
|`data`|`bytes`|some additional data|


## Events
### SetMaxNetworkLimit
Emitted when a subnetwork's maximum limit is set.


```solidity
event SetMaxNetworkLimit(bytes32 indexed subnetwork, uint256 amount);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`subnetwork`|`bytes32`|full identifier of the subnetwork (address of the network concatenated with the uint96 identifier)|
|`amount`|`uint256`|new maximum subnetwork's limit (how much stake the subnetwork is ready to get)|

### OnSlash
Emitted when a slash happens.


```solidity
event OnSlash(bytes32 indexed subnetwork, address indexed operator, uint256 amount, uint48 captureTimestamp);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`subnetwork`|`bytes32`|full identifier of the subnetwork (address of the network concatenated with the uint96 identifier)|
|`operator`|`address`|address of the operator|
|`amount`|`uint256`|amount of the collateral to be slashed|
|`captureTimestamp`|`uint48`|time point when the stake was captured|

### SetHook
Emitted when a hook is set.


```solidity
event SetHook(address indexed hook);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`hook`|`address`|address of the hook|

## Errors
### AlreadySet

```solidity
error AlreadySet();
```

### InsufficientHookGas

```solidity
error InsufficientHookGas();
```

### NotNetwork

```solidity
error NotNetwork();
```

### NotSlasher

```solidity
error NotSlasher();
```

### NotVault

```solidity
error NotVault();
```

## Structs
### BaseParams
Base parameters needed for delegators' deployment.


```solidity
struct BaseParams {
    address defaultAdminRoleHolder;
    address hook;
    address hookSetRoleHolder;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`defaultAdminRoleHolder`|`address`|address of the initial DEFAULT_ADMIN_ROLE holder|
|`hook`|`address`|address of the hook contract|
|`hookSetRoleHolder`|`address`|address of the initial HOOK_SET_ROLE holder|

### StakeBaseHints
Base hints for a stake.


```solidity
struct StakeBaseHints {
    bytes operatorVaultOptInHint;
    bytes operatorNetworkOptInHint;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`operatorVaultOptInHint`|`bytes`|hint for the operator-vault opt-in|
|`operatorNetworkOptInHint`|`bytes`|hint for the operator-network opt-in|

