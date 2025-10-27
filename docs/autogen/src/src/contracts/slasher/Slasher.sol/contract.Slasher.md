# Slasher
[Git Source](https://github.com/symbioticfi/core/blob/34733e78ecb0c08640f857df155aa6d467dd9462/src/contracts/slasher/Slasher.sol)

**Inherits:**
[BaseSlasher](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/contracts/slasher/BaseSlasher.sol/abstract.BaseSlasher.md), [ISlasher](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/interfaces/slasher/ISlasher.sol/interface.ISlasher.md)


## Functions
### constructor


```solidity
constructor(address vaultFactory, address networkMiddlewareService, address slasherFactory, uint64 entityType)
    BaseSlasher(vaultFactory, networkMiddlewareService, slasherFactory, entityType);
```

### slash

Perform a slash using a subnetwork for a particular operator by a given amount using hints.

Only a network middleware can call this function.


```solidity
function slash(bytes32 subnetwork, address operator, uint256 amount, uint48 captureTimestamp, bytes calldata hints)
    external
    nonReentrant
    onlyNetworkMiddleware(subnetwork)
    returns (uint256 slashedAmount);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`subnetwork`|`bytes32`|full identifier of the subnetwork (address of the network concatenated with the uint96 identifier)|
|`operator`|`address`|address of the operator|
|`amount`|`uint256`|maximum amount of the collateral to be slashed|
|`captureTimestamp`|`uint48`|time point when the stake was captured|
|`hints`|`bytes`|hints for checkpoints' indexes|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`slashedAmount`|`uint256`|virtual amount of the collateral slashed|


### __initialize


```solidity
function __initialize(
    address,
    /* vault_ */
    bytes memory data
)
    internal
    override
    returns (BaseParams memory);
```

