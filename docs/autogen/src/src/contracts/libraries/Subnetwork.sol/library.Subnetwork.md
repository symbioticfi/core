# Subnetwork
[Git Source](https://github.com/symbioticfi/core/blob/0c5792225777a2fa2f15f10dba9650eb44861800/src/contracts/libraries/Subnetwork.sol)

This library adds functions to work with subnetworks.


## Functions
### subnetwork


```solidity
function subnetwork(address network_, uint96 identifier_) internal pure returns (bytes32);
```

### network


```solidity
function network(bytes32 subnetwork_) internal pure returns (address);
```

### identifier


```solidity
function identifier(bytes32 subnetwork_) internal pure returns (uint96);
```

