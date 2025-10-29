# FullRestakeDelegator
[Git Source](https://github.com/symbioticfi/core/blob/454f363c3e06eeffbe2515756b914d72c84b8ae4/src/contracts/delegator/FullRestakeDelegator.sol)

**Inherits:**
[BaseDelegator](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/contracts/delegator/BaseDelegator.sol/abstract.BaseDelegator.md), [IFullRestakeDelegator](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/interfaces/delegator/IFullRestakeDelegator.sol/interface.IFullRestakeDelegator.md)


## State Variables
### NETWORK_LIMIT_SET_ROLE
Get a subnetwork limit setter's role.


```solidity
bytes32 public constant NETWORK_LIMIT_SET_ROLE = keccak256("NETWORK_LIMIT_SET_ROLE")
```


### OPERATOR_NETWORK_LIMIT_SET_ROLE
Get an operator-subnetwork limit setter's role.


```solidity
bytes32 public constant OPERATOR_NETWORK_LIMIT_SET_ROLE = keccak256("OPERATOR_NETWORK_LIMIT_SET_ROLE")
```


### _networkLimit

```solidity
mapping(bytes32 subnetwork => Checkpoints.Trace256 value) internal _networkLimit
```


### _operatorNetworkLimit

```solidity
mapping(bytes32 subnetwork => mapping(address operator => Checkpoints.Trace256 value)) internal
    _operatorNetworkLimit
```


## Functions
### constructor


```solidity
constructor(
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


### operatorNetworkLimitAt

Get an operator's limit for a subnetwork at a given timestamp using a hint
(how much stake the vault curator is ready to give to the operator for the subnetwork).


```solidity
function operatorNetworkLimitAt(bytes32 subnetwork, address operator, uint48 timestamp, bytes memory hint)
    public
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
function operatorNetworkLimit(bytes32 subnetwork, address operator) public view returns (uint256);
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
function setNetworkLimit(bytes32 subnetwork, uint256 amount) external onlyRole(NETWORK_LIMIT_SET_ROLE);
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
function setOperatorNetworkLimit(bytes32 subnetwork, address operator, uint256 amount)
    external
    onlyRole(OPERATOR_NETWORK_LIMIT_SET_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`subnetwork`|`bytes32`|full identifier of the subnetwork (address of the network concatenated with the uint96 identifier)|
|`operator`|`address`|address of the operator|
|`amount`|`uint256`|new limit of the operator for the subnetwork|


### _stakeAt


```solidity
function _stakeAt(bytes32 subnetwork, address operator, uint48 timestamp, bytes memory hints)
    internal
    view
    override
    returns (uint256, bytes memory);
```

### _stake


```solidity
function _stake(bytes32 subnetwork, address operator) internal view override returns (uint256);
```

### _setMaxNetworkLimit


```solidity
function _setMaxNetworkLimit(bytes32 subnetwork, uint256 amount) internal override;
```

### __initialize


```solidity
function __initialize(address, bytes memory data) internal override returns (IBaseDelegator.BaseParams memory);
```

