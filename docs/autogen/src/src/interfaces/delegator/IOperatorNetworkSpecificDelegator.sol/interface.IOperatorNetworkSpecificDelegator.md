# IOperatorNetworkSpecificDelegator
[Git Source](https://github.com/symbioticfi/core/blob/72d444d21da2b07516bb08def1e4b57d35cf27c3/src/interfaces/delegator/IOperatorNetworkSpecificDelegator.sol)

**Inherits:**
[IBaseDelegator](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/interfaces/delegator/IBaseDelegator.sol/interface.IBaseDelegator.md)


## Functions
### OPERATOR_REGISTRY

Get the operator registry's address.


```solidity
function OPERATOR_REGISTRY() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|address of the operator registry|


### network

Get a network the vault delegates funds to.


```solidity
function network() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|address of the network|


### operator

Get an operator managing the vault's funds.


```solidity
function operator() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|address of the operator|


### maxNetworkLimitAt

Get a particular subnetwork's maximum limit at a given timestamp using a hint
(meaning the subnetwork is not ready to get more as a stake).


```solidity
function maxNetworkLimitAt(bytes32 subnetwork, uint48 timestamp, bytes memory hint) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`subnetwork`|`bytes32`|full identifier of the subnetwork (address of the network concatenated with the uint96 identifier)|
|`timestamp`|`uint48`|time point to get the maximum subnetwork limit at|
|`hint`|`bytes`|hint for checkpoint index|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|maximum limit of the subnetwork|


## Errors
### InvalidNetwork

```solidity
error InvalidNetwork();
```

### NotOperator

```solidity
error NotOperator();
```

## Structs
### StakeHints
Hints for a stake.


```solidity
struct StakeHints {
    bytes baseHints;
    bytes activeStakeHint;
    bytes maxNetworkLimitHint;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`baseHints`|`bytes`|base hints|
|`activeStakeHint`|`bytes`|hint for the active stake checkpoint|
|`maxNetworkLimitHint`|`bytes`|hint for the maximum subnetwork limit checkpoint|

### InitParams
Initial parameters needed for an operator-network-specific delegator deployment.


```solidity
struct InitParams {
    IBaseDelegator.BaseParams baseParams;
    address network;
    address operator;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`baseParams`|`IBaseDelegator.BaseParams`|base parameters for delegators' deployment|
|`network`|`address`|address of the single network|
|`operator`|`address`|address of the single operator|

