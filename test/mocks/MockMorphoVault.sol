// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockMorphoVault {
    IERC20 public immutable asset;

    uint256 public totalShares;
    mapping(address account => uint256 shares) public sharesOf;

    constructor(address asset_) {
        asset = IERC20(asset_);
    }

    function maxWithdraw(address owner) external view returns (uint256) {
        if (totalShares == 0) {
            return 0;
        }
        return sharesOf[owner] * asset.balanceOf(address(this)) / totalShares;
    }

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        uint256 totalAssetsBefore = asset.balanceOf(address(this));
        asset.transferFrom(msg.sender, address(this), assets);

        if (totalShares == 0 || totalAssetsBefore == 0) {
            shares = assets;
        } else {
            shares = assets * totalShares / totalAssetsBefore;
        }

        sharesOf[receiver] += shares;
        totalShares += shares;
        return shares;
    }

    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares) {
        uint256 totalAssets = asset.balanceOf(address(this));
        if (totalAssets == 0 || totalShares == 0) {
            return 0;
        }
        shares = assets * totalShares / totalAssets;
        if (shares > sharesOf[owner]) {
            shares = sharesOf[owner];
            assets = shares * totalAssets / totalShares;
        }

        sharesOf[owner] -= shares;
        totalShares -= shares;
        asset.transfer(receiver, assets);
        return shares;
    }

    function balanceOf(address account) external view virtual returns (uint256) {
        return sharesOf[account];
    }

    function previewRedeem(uint256 shares) external view virtual returns (uint256) {
        if (totalShares == 0) {
            return 0;
        }
        return shares * asset.balanceOf(address(this)) / totalShares;
    }

    function donateYield(uint256 amount) external {
        asset.transferFrom(msg.sender, address(this), amount);
    }
}
