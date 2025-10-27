# MigratableEntityProxy
[Git Source](https://github.com/symbioticfi/core/blob/4905f62919b30e0606fff3aaa7fcd52bf8ee3d3e/src/contracts/common/MigratableEntityProxy.sol)

**Inherits:**
ERC1967Proxy, [IMigratableEntityProxy](/Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/interfaces/common/IMigratableEntityProxy.sol/interface.IMigratableEntityProxy.md)


## State Variables
### _admin

```solidity
address private immutable _admin
```


## Functions
### constructor

Initializes an upgradeable proxy managed by `msg.sender`,
backed by the implementation at `logic`, and optionally initialized with `data` as explained in
[ERC1967Proxy-constructor](//Users/andreikorokhov/symbiotic/core/docs/autogen/src/src/contracts/common/MigratablesFactory.sol/contract.MigratablesFactory.md#constructor).


```solidity
constructor(address logic, bytes memory data) ERC1967Proxy(logic, data);
```

### upgradeToAndCall

Upgrade the proxy to a new implementation and call a function on the new implementation.


```solidity
function upgradeToAndCall(address newImplementation, bytes calldata data) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newImplementation`|`address`|address of the new implementation|
|`data`|`bytes`|data to call on the new implementation|


### _proxyAdmin

Returns the admin of this proxy.


```solidity
function _proxyAdmin() internal view returns (address);
```

## Errors
### ProxyDeniedAdminAccess
The proxy caller is the current admin, and can't fallback to the proxy target.


```solidity
error ProxyDeniedAdminAccess();
```

