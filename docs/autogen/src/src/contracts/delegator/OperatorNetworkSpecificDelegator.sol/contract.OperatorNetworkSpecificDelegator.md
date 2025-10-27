# OperatorNetworkSpecificDelegator
[Git Source](https://github.com/symbioticfi/core/blob/34733e78ecb0c08640f857df155aa6d467dd9462/src/contracts/delegator/OperatorNetworkSpecificDelegator.sol)

**Inherits:**
[BaseDelegator](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/contracts/delegator/BaseDelegator.sol/abstract.BaseDelegator.md), [IOperatorNetworkSpecificDelegator](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/interfaces/delegator/IOperatorNetworkSpecificDelegator.sol/interface.IOperatorNetworkSpecificDelegator.md)


## State Variables
### OPERATOR_REGISTRY
Get the operator registry's address.


```solidity
address public immutable OPERATOR_REGISTRY
```


### _maxNetworkLimit

```solidity
mapping(bytes32 subnetwork => Checkpoints.Trace256 value) internal _maxNetworkLimit
```


### network
Get a network the vault delegates funds to.


```solidity
address public network
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

### maxNetworkLimitAt

Get a particular subnetwork's maximum limit at a given timestamp using a hint
(meaning the subnetwork is not ready to get more as a stake).


```solidity
function maxNetworkLimitAt(bytes32 subnetwork, uint48 timestamp, bytes memory hint) public view returns (uint256);
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

