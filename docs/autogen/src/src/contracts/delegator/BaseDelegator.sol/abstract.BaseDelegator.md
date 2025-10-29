# BaseDelegator
[Git Source](https://github.com/symbioticfi/core/blob/72d444d21da2b07516bb08def1e4b57d35cf27c3/src/contracts/delegator/BaseDelegator.sol)

**Inherits:**
[Entity](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/contracts/common/Entity.sol/abstract.Entity.md), [StaticDelegateCallable](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/contracts/common/StaticDelegateCallable.sol/abstract.StaticDelegateCallable.md), AccessControlUpgradeable, ReentrancyGuardUpgradeable, [IBaseDelegator](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/interfaces/delegator/IBaseDelegator.sol/interface.IBaseDelegator.md)


## State Variables
### HOOK_GAS_LIMIT
Get a gas limit for the hook.


```solidity
uint256 public constant HOOK_GAS_LIMIT = 250_000
```


### HOOK_RESERVE
Get a reserve gas between the gas limit check and the hook's execution.


```solidity
uint256 public constant HOOK_RESERVE = 20_000
```


### HOOK_SET_ROLE
Get a hook setter's role.


```solidity
bytes32 public constant HOOK_SET_ROLE = keccak256("HOOK_SET_ROLE")
```


### NETWORK_REGISTRY
Get the network registry's address.


```solidity
address public immutable NETWORK_REGISTRY
```


### VAULT_FACTORY
Get the vault factory's address.


```solidity
address public immutable VAULT_FACTORY
```


### OPERATOR_VAULT_OPT_IN_SERVICE
Get the operator-vault opt-in service's address.


```solidity
address public immutable OPERATOR_VAULT_OPT_IN_SERVICE
```


### OPERATOR_NETWORK_OPT_IN_SERVICE
Get the operator-network opt-in service's address.


```solidity
address public immutable OPERATOR_NETWORK_OPT_IN_SERVICE
```


### vault
Get the vault's address.


```solidity
address public vault
```


### hook
Get the hook's address.

The hook can have arbitrary logic under certain functions, however, it doesn't affect the stake guarantees.


```solidity
address public hook
```


### maxNetworkLimit
Get a particular subnetwork's maximum limit
(meaning the subnetwork is not ready to get more as a stake).


```solidity
mapping(bytes32 subnetwork => uint256 value) public maxNetworkLimit
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
) Entity(delegatorFactory, entityType);
```

### VERSION

Get a version of the delegator (different versions mean different interfaces).

Must return 1 for this one.


```solidity
function VERSION() external pure returns (uint64);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint64`|version of the delegator|


### stakeAt

Get a stake that a given subnetwork could be able to slash for a certain operator at a given timestamp
until the end of the consequent epoch using hints (if no cross-slashing and no slashings by the subnetwork).

Warning: it is not safe to use timestamp >= current one for the stake capturing, as it can change later.


```solidity
function stakeAt(bytes32 subnetwork, address operator, uint48 timestamp, bytes memory hints)
    public
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
function setMaxNetworkLimit(uint96 identifier, uint256 amount) external nonReentrant;
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
function setHook(address hook_) external nonReentrant onlyRole(HOOK_SET_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`hook_`|`address`||


### onSlash

Called when a slash happens.

Only the vault's slasher can call this function.


```solidity
function onSlash(bytes32 subnetwork, address operator, uint256 amount, uint48 captureTimestamp, bytes memory data)
    external
    nonReentrant;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`subnetwork`|`bytes32`|full identifier of the subnetwork (address of the network concatenated with the uint96 identifier)|
|`operator`|`address`|address of the operator|
|`amount`|`uint256`|amount of the collateral slashed|
|`captureTimestamp`|`uint48`|time point when the stake was captured|
|`data`|`bytes`|some additional data|


### _initialize


```solidity
function _initialize(bytes calldata data) internal override;
```

### _stakeAt


```solidity
function _stakeAt(bytes32 subnetwork, address operator, uint48 timestamp, bytes memory hints)
    internal
    view
    virtual
    returns (uint256, bytes memory);
```

### _stake


```solidity
function _stake(bytes32 subnetwork, address operator) internal view virtual returns (uint256);
```

### _setMaxNetworkLimit


```solidity
function _setMaxNetworkLimit(bytes32 subnetwork, uint256 amount) internal virtual;
```

### __initialize


```solidity
function __initialize(address vault_, bytes memory data) internal virtual returns (BaseParams memory);
```

