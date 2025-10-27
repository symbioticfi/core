# Entity
[Git Source](https://github.com/symbioticfi/core/blob/4905f62919b30e0606fff3aaa7fcd52bf8ee3d3e/src/contracts/common/Entity.sol)

**Inherits:**
Initializable, [IEntity](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/interfaces/common/IEntity.sol/interface.IEntity.md)


## State Variables
### FACTORY
Get the factory's address.


```solidity
address public immutable FACTORY
```


### TYPE
Get the entity's type.


```solidity
uint64 public immutable TYPE
```


## Functions
### constructor


```solidity
constructor(address factory, uint64 type_) ;
```

### initialize

Initialize this entity contract by using a given data.


```solidity
function initialize(bytes calldata data) external initializer;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`data`|`bytes`|some data to use|


### _initialize


```solidity
function _initialize(
    bytes calldata /* data */
)
    internal
    virtual;
```

