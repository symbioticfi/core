# MigratableEntity
[Git Source](https://github.com/symbioticfi/core/blob/454f363c3e06eeffbe2515756b914d72c84b8ae4/src/contracts/common/MigratableEntity.sol)

**Inherits:**
Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, [IMigratableEntity](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/interfaces/common/IMigratableEntity.sol/interface.IMigratableEntity.md)


## State Variables
### FACTORY
Get the factory's address.


```solidity
address public immutable FACTORY
```


### __gap

```solidity
uint256[10] private __gap
```


## Functions
### notInitialized


```solidity
modifier notInitialized() ;
```

### constructor


```solidity
constructor(address factory) ;
```

### version

Get the entity's version.

Starts from 1.


```solidity
function version() external view returns (uint64);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint64`|version of the entity|


### initialize

Initialize this entity contract by using a given data and setting a particular version and owner.


```solidity
function initialize(uint64 initialVersion, address owner_, bytes calldata data)
    external
    notInitialized
    reinitializer(initialVersion);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`initialVersion`|`uint64`|initial version of the entity|
|`owner_`|`address`||
|`data`|`bytes`|some data to use|


### migrate

Migrate this entity to a particular newer version using a given data.


```solidity
function migrate(uint64 newVersion, bytes calldata data) external nonReentrant;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newVersion`|`uint64`|new version of the entity|
|`data`|`bytes`|some data to use|


### _migrateInternal


```solidity
function _migrateInternal(uint64 oldVersion, uint64 newVersion, bytes calldata data)
    private
    reinitializer(newVersion);
```

### _initialize


```solidity
function _initialize(
    uint64,
    /* initialVersion */
    address,
    /* owner */
    bytes memory /* data */
)
    internal
    virtual;
```

### _migrate


```solidity
function _migrate(
    uint64,
    /* oldVersion */
    uint64,
    /* newVersion */
    bytes calldata /* data */
)
    internal
    virtual;
```

