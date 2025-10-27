# IOperatorSpecificDelegator
[Git Source](https://github.com/symbioticfi/core/blob/df9ca184c8ea82a887fc1922bce2558281ce8e60/src/interfaces/delegator/IOperatorSpecificDelegator.sol)

**Inherits:**
[IBaseDelegator](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/interfaces/delegator/IBaseDelegator.sol/interface.IBaseDelegator.md)


## Functions
### NETWORK_LIMIT_SET_ROLE

Get a subnetwork limit setter's role.


```solidity
function NETWORK_LIMIT_SET_ROLE() external view returns (bytes32);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes32`|identifier of the subnetwork limit setter role|


### OPERATOR_REGISTRY

Get the operator registry's address.


```solidity
function OPERATOR_REGISTRY() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|address of the operator registry|


### operator

Get an operator managing the vault's funds.


```solidity
function operator() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|address of the operator|


### networkLimitAt

Get a subnetwork's limit at a given timestamp using a hint
(how much stake the vault curator is ready to give to the subnetwork).


```solidity
function networkLimitAt(bytes32 subnetwork, uint48 timestamp, bytes memory hint) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`subnetwork`|`bytes32`|full identifier of the subnetwork (address of the network concatenated with the uint96 identifier)|
|`timestamp`|`uint48`|time point to get the subnetwork limit at|
|`hint`|`bytes`|hint for checkpoint index|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|limit of the subnetwork at the given timestamp|


### networkLimit

Get a subnetwork's limit (how much stake the vault curator is ready to give to the subnetwork).


```solidity
function networkLimit(bytes32 subnetwork) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`subnetwork`|`bytes32`|full identifier of the subnetwork (address of the network concatenated with the uint96 identifier)|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|limit of the subnetwork|


### setNetworkLimit

Set a subnetwork's limit (how much stake the vault curator is ready to give to the subnetwork).

Only a NETWORK_LIMIT_SET_ROLE holder can call this function.


```solidity
function setNetworkLimit(bytes32 subnetwork, uint256 amount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`subnetwork`|`bytes32`|full identifier of the subnetwork (address of the network concatenated with the uint96 identifier)|
|`amount`|`uint256`|new limit of the subnetwork|


## Events
### SetNetworkLimit
Emitted when a subnetwork's limit is set.


```solidity
event SetNetworkLimit(bytes32 indexed subnetwork, uint256 amount);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`subnetwork`|`bytes32`|full identifier of the subnetwork (address of the network concatenated with the uint96 identifier)|
|`amount`|`uint256`|new subnetwork's limit (how much stake the vault curator is ready to give to the subnetwork)|

## Errors
### DuplicateRoleHolder

```solidity
error DuplicateRoleHolder();
```

### ExceedsMaxNetworkLimit

```solidity
error ExceedsMaxNetworkLimit();
```

### MissingRoleHolders

```solidity
error MissingRoleHolders();
```

### NotOperator

```solidity
error NotOperator();
```

### ZeroAddressRoleHolder

```solidity
error ZeroAddressRoleHolder();
```

## Structs
### StakeHints
Hints for a stake.


```solidity
struct StakeHints {
    bytes baseHints;
    bytes activeStakeHint;
    bytes networkLimitHint;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`baseHints`|`bytes`|base hints|
|`activeStakeHint`|`bytes`|hint for the active stake checkpoint|
|`networkLimitHint`|`bytes`|hint for the subnetwork limit checkpoint|

### InitParams
Initial parameters needed for an operator-specific delegator deployment.


```solidity
struct InitParams {
    IBaseDelegator.BaseParams baseParams;
    address[] networkLimitSetRoleHolders;
    address operator;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`baseParams`|`IBaseDelegator.BaseParams`|base parameters for delegators' deployment|
|`networkLimitSetRoleHolders`|`address[]`|array of addresses of the initial NETWORK_LIMIT_SET_ROLE holders|
|`operator`|`address`|address of the single operator|

