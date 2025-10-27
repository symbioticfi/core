# IFullRestakeDelegator
[Git Source](https://github.com/symbioticfi/core/blob/34733e78ecb0c08640f857df155aa6d467dd9462/src/interfaces/delegator/IFullRestakeDelegator.sol)

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


### OPERATOR_NETWORK_LIMIT_SET_ROLE

Get an operator-subnetwork limit setter's role.


```solidity
function OPERATOR_NETWORK_LIMIT_SET_ROLE() external view returns (bytes32);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes32`|identifier of the operator-subnetwork limit setter role|


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


### operatorNetworkLimitAt

Get an operator's limit for a subnetwork at a given timestamp using a hint
(how much stake the vault curator is ready to give to the operator for the subnetwork).


```solidity
function operatorNetworkLimitAt(bytes32 subnetwork, address operator, uint48 timestamp, bytes memory hint)
    external
    view
    returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`subnetwork`|`bytes32`|full identifier of the subnetwork (address of the network concatenated with the uint96 identifier)|
|`operator`|`address`|address of the operator|
|`timestamp`|`uint48`|time point to get the operator's limit for the subnetwork at|
|`hint`|`bytes`|hint for checkpoint index|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|limit of the operator for the subnetwork at the given timestamp|


### operatorNetworkLimit

Get an operator's limit for a subnetwork.
(how much stake the vault curator is ready to give to the operator for the subnetwork)


```solidity
function operatorNetworkLimit(bytes32 subnetwork, address operator) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`subnetwork`|`bytes32`|full identifier of the subnetwork (address of the network concatenated with the uint96 identifier)|
|`operator`|`address`|address of the operator|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|limit of the operator for the subnetwork|


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


### setOperatorNetworkLimit

Set an operator's limit for a subnetwork.
(how much stake the vault curator is ready to give to the operator for the subnetwork)

Only an OPERATOR_NETWORK_LIMIT_SET_ROLE holder can call this function.


```solidity
function setOperatorNetworkLimit(bytes32 subnetwork, address operator, uint256 amount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`subnetwork`|`bytes32`|full identifier of the subnetwork (address of the network concatenated with the uint96 identifier)|
|`operator`|`address`|address of the operator|
|`amount`|`uint256`|new limit of the operator for the subnetwork|


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

### SetOperatorNetworkLimit
Emitted when an operator's limit for a subnetwork is set.


```solidity
event SetOperatorNetworkLimit(bytes32 indexed subnetwork, address indexed operator, uint256 amount);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`subnetwork`|`bytes32`|full identifier of the subnetwork (address of the network concatenated with the uint96 identifier)|
|`operator`|`address`|address of the operator|
|`amount`|`uint256`|new operator's limit for the subnetwork (how much stake the vault curator is ready to give to the operator for the subnetwork)|

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
    bytes operatorNetworkLimitHint;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`baseHints`|`bytes`|base hints|
|`activeStakeHint`|`bytes`|hint for the active stake checkpoint|
|`networkLimitHint`|`bytes`|hint for the subnetwork limit checkpoint|
|`operatorNetworkLimitHint`|`bytes`|hint for the operator-subnetwork limit checkpoint|

### InitParams
Initial parameters needed for a full restaking delegator deployment.


```solidity
struct InitParams {
    IBaseDelegator.BaseParams baseParams;
    address[] networkLimitSetRoleHolders;
    address[] operatorNetworkLimitSetRoleHolders;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`baseParams`|`IBaseDelegator.BaseParams`|base parameters for delegators' deployment|
|`networkLimitSetRoleHolders`|`address[]`|array of addresses of the initial NETWORK_LIMIT_SET_ROLE holders|
|`operatorNetworkLimitSetRoleHolders`|`address[]`|array of addresses of the initial OPERATOR_NETWORK_LIMIT_SET_ROLE holders|

