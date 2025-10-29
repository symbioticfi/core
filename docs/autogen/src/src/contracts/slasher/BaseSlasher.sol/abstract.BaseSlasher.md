# BaseSlasher
[Git Source](https://github.com/symbioticfi/core/blob/72d444d21da2b07516bb08def1e4b57d35cf27c3/src/contracts/slasher/BaseSlasher.sol)

**Inherits:**
[Entity](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/contracts/common/Entity.sol/abstract.Entity.md), [StaticDelegateCallable](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/contracts/common/StaticDelegateCallable.sol/abstract.StaticDelegateCallable.md), ReentrancyGuardUpgradeable, [IBaseSlasher](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/interfaces/slasher/IBaseSlasher.sol/interface.IBaseSlasher.md)


## State Variables
### BURNER_GAS_LIMIT
Get a gas limit for the burner.


```solidity
uint256 public constant BURNER_GAS_LIMIT = 150_000
```


### BURNER_RESERVE
Get a reserve gas between the gas limit check and the burner's execution.


```solidity
uint256 public constant BURNER_RESERVE = 20_000
```


### VAULT_FACTORY
Get the vault factory's address.


```solidity
address public immutable VAULT_FACTORY
```


### NETWORK_MIDDLEWARE_SERVICE
Get the network middleware service's address.


```solidity
address public immutable NETWORK_MIDDLEWARE_SERVICE
```


### vault
Get the vault's address.


```solidity
address public vault
```


### isBurnerHook
Get if the burner is needed to be called on a slashing.


```solidity
bool public isBurnerHook
```


### latestSlashedCaptureTimestamp
Get the latest capture timestamp that was slashed on a subnetwork.


```solidity
mapping(bytes32 subnetwork => mapping(address operator => uint48 value)) public latestSlashedCaptureTimestamp
```


### _cumulativeSlash

```solidity
mapping(bytes32 subnetwork => mapping(address operator => Checkpoints.Trace256 amount)) internal _cumulativeSlash
```


## Functions
### onlyNetworkMiddleware


```solidity
modifier onlyNetworkMiddleware(bytes32 subnetwork) ;
```

### constructor


```solidity
constructor(address vaultFactory, address networkMiddlewareService, address slasherFactory, uint64 entityType)
    Entity(slasherFactory, entityType);
```

### cumulativeSlashAt

Get a cumulative slash amount for an operator on a subnetwork until a given timestamp (inclusively) using a hint.


```solidity
function cumulativeSlashAt(bytes32 subnetwork, address operator, uint48 timestamp, bytes memory hint)
    public
    view
    returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`subnetwork`|`bytes32`|full identifier of the subnetwork (address of the network concatenated with the uint96 identifier)|
|`operator`|`address`|address of the operator|
|`timestamp`|`uint48`|time point to get the cumulative slash amount until (inclusively)|
|`hint`|`bytes`|hint for the checkpoint index|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|cumulative slash amount until the given timestamp (inclusively)|


### cumulativeSlash

Get a cumulative slash amount for an operator on a subnetwork.


```solidity
function cumulativeSlash(bytes32 subnetwork, address operator) public view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`subnetwork`|`bytes32`|full identifier of the subnetwork (address of the network concatenated with the uint96 identifier)|
|`operator`|`address`|address of the operator|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|cumulative slash amount|


### slashableStake

Get a slashable amount of a stake got at a given capture timestamp using hints.


```solidity
function slashableStake(bytes32 subnetwork, address operator, uint48 captureTimestamp, bytes memory hints)
    public
    view
    returns (uint256 amount);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`subnetwork`|`bytes32`|full identifier of the subnetwork (address of the network concatenated with the uint96 identifier)|
|`operator`|`address`|address of the operator|
|`captureTimestamp`|`uint48`|time point to get the stake amount at|
|`hints`|`bytes`|hints for the checkpoints' indexes|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`amount`|`uint256`|slashable amount of the stake|


### _slashableStake


```solidity
function _slashableStake(bytes32 subnetwork, address operator, uint48 captureTimestamp, bytes memory hints)
    internal
    view
    returns (uint256 slashableStake_, uint256 stakeAmount);
```

### _checkNetworkMiddleware


```solidity
function _checkNetworkMiddleware(bytes32 subnetwork) internal view;
```

### _updateLatestSlashedCaptureTimestamp


```solidity
function _updateLatestSlashedCaptureTimestamp(bytes32 subnetwork, address operator, uint48 captureTimestamp)
    internal;
```

### _updateCumulativeSlash


```solidity
function _updateCumulativeSlash(bytes32 subnetwork, address operator, uint256 amount) internal;
```

### _delegatorOnSlash


```solidity
function _delegatorOnSlash(
    bytes32 subnetwork,
    address operator,
    uint256 amount,
    uint48 captureTimestamp,
    bytes memory data
) internal;
```

### _vaultOnSlash


```solidity
function _vaultOnSlash(uint256 amount, uint48 captureTimestamp) internal;
```

### _burnerOnSlash


```solidity
function _burnerOnSlash(bytes32 subnetwork, address operator, uint256 amount, uint48 captureTimestamp) internal;
```

### _initialize


```solidity
function _initialize(bytes calldata data) internal override;
```

### __initialize


```solidity
function __initialize(address vault_, bytes memory data) internal virtual returns (BaseParams memory);
```

