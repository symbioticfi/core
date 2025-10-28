# Subnetwork
[Git Source](https://github.com/symbioticfi/core/blob/45a7dbdd18fc5ac73ecf7310fc6816999bb8eef3/src/contracts/libraries/Subnetwork.sol)

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

