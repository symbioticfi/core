# ERC4626Math
[Git Source](https://github.com/symbioticfi/core/blob/5ab692fe7f696ff6aee61a77fae37dc444e1c86e/src/contracts/libraries/ERC4626Math.sol)

This library adds helper functions for ERC4626 math operations.


## Functions
### previewDeposit


```solidity
function previewDeposit(uint256 assets, uint256 totalShares, uint256 totalAssets) internal pure returns (uint256);
```

### previewMint


```solidity
function previewMint(uint256 shares, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256);
```

### previewWithdraw


```solidity
function previewWithdraw(uint256 assets, uint256 totalShares, uint256 totalAssets) internal pure returns (uint256);
```

### previewRedeem


```solidity
function previewRedeem(uint256 shares, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256);
```

### convertToShares

Internal conversion function (from assets to shares) with support for rounding direction.


```solidity
function convertToShares(uint256 assets, uint256 totalShares, uint256 totalAssets, Math.Rounding rounding)
    internal
    pure
    returns (uint256);
```

### convertToAssets

Internal conversion function (from shares to assets) with support for rounding direction.


```solidity
function convertToAssets(uint256 shares, uint256 totalAssets, uint256 totalShares, Math.Rounding rounding)
    internal
    pure
    returns (uint256);
```

### _decimalsOffset


```solidity
function _decimalsOffset() private pure returns (uint8);
```

