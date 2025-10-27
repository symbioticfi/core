# Subnetwork
[Git Source](https://github.com/symbioticfi/core/blob/34733e78ecb0c08640f857df155aa6d467dd9462/src/contracts/libraries/Subnetwork.sol)

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

