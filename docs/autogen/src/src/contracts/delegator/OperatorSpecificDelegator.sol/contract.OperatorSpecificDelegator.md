# OperatorSpecificDelegator
[Git Source](https://github.com/symbioticfi/core/blob/0c5792225777a2fa2f15f10dba9650eb44861800/src/contracts/delegator/OperatorSpecificDelegator.sol)

**Inherits:**
[BaseDelegator](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/contracts/delegator/BaseDelegator.sol/abstract.BaseDelegator.md), [IOperatorSpecificDelegator](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/interfaces/delegator/IOperatorSpecificDelegator.sol/interface.IOperatorSpecificDelegator.md)


## State Variables
### NETWORK_LIMIT_SET_ROLE
Get a subnetwork limit setter's role.


```solidity
bytes32 public constant NETWORK_LIMIT_SET_ROLE = keccak256("NETWORK_LIMIT_SET_ROLE")
```


### OPERATOR_REGISTRY
Get the operator registry's address.


```solidity
address public immutable OPERATOR_REGISTRY
```


### _networkLimit

```solidity
mapping(bytes32 subnetwork => Checkpoints.Trace256 value) internal _networkLimit
```


### operator
Get an operator managing the vault's funds.


```solidity
address public operator
```


## Functions
### constructor


```solidity
constructor(
    address operatorRegistry,
    address networkRegistry,
    address vaultFactory,
    address operatorVaultOptInService,
    address operatorNetworkOptInService,
    address delegatorFactory,
    uint64 entityType
)
    BaseDelegator(
        networkRegistry,
        vaultFactory,
        operatorVaultOptInService,
        operatorNetworkOptInService,
        delegatorFactory,
        entityType
    );
```

### networkLimitAt

Get a subnetwork's limit at a given timestamp using a hint
(how much stake the vault curator is ready to give to the subnetwork).


```solidity
function networkLimitAt(bytes32 subnetwork, uint48 timestamp, bytes memory hint) public view returns (uint256);
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
function networkLimit(bytes32 subnetwork) public view returns (uint256);
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
function setNetworkLimit(bytes32 subnetwork, uint256 amount) external onlyRole(NETWORK_LIMIT_SET_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`subnetwork`|`bytes32`|full identifier of the subnetwork (address of the network concatenated with the uint96 identifier)|
|`amount`|`uint256`|new limit of the subnetwork|


### _stakeAt


```solidity
function _stakeAt(bytes32 subnetwork, address operator_, uint48 timestamp, bytes memory hints)
    internal
    view
    override
    returns (uint256, bytes memory);
```

### _stake


```solidity
function _stake(bytes32 subnetwork, address operator_) internal view override returns (uint256);
```

### _setMaxNetworkLimit


```solidity
function _setMaxNetworkLimit(bytes32 subnetwork, uint256 amount) internal override;
```

### __initialize


```solidity
function __initialize(address, bytes memory data) internal override returns (IBaseDelegator.BaseParams memory);
```

