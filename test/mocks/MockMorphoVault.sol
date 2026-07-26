// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title MockMorphoVault
/// @notice Canonical ERC-4626 stand-in for a Morpho Vault V2. Uses OpenZeppelin's virtual-share
///         accounting so deposits are inflation-protected and withdrawals round shares up, exactly
///         like the real vault. `totalAssets()` tracks the vault's asset balance, so yield is
///         simulated by transferring assets in via `donateYield`.
contract MockMorphoVault is ERC4626 {
    constructor(address asset_) ERC20("Mock Morpho Vault", "mMV") ERC4626(IERC20(asset_)) {}

    /// @dev Simulates accrued yield: assets flow in without minting shares, raising the share price.
    function donateYield(uint256 amount) external {
        IERC20(asset()).transferFrom(msg.sender, address(this), amount);
    }
}
