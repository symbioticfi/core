// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IAdapterBase} from "../../src/interfaces/vault/IAdapterBase.sol";

contract MockAdapter is IAdapterBase {
    IERC20 public immutable assetToken;
    address public immutable vault;
    uint256 public allocated;
    bool public shouldFail;

    constructor(address vault_, address assetToken_) {
        vault = vault_;
        assetToken = IERC20(assetToken_);
    }

    function setShouldFail(bool value) external {
        shouldFail = value;
    }

    function allocatable(address) external view returns (uint256) {
        if (shouldFail) {
            return 0;
        }
        return type(uint256).max;
    }

    function deallocatable(address vault_) external view returns (uint256) {
        if (vault_ != vault || shouldFail) {
            return 0;
        }
        return assetToken.balanceOf(address(this));
    }

    function allocate(uint256 amount) external {
        allocated += amount;
    }

    function deallocate(uint256 amount) external returns (uint256) {
        if (shouldFail) {
            return 0;
        }

        uint256 balance = assetToken.balanceOf(address(this));
        uint256 deallocated = amount <= balance ? amount : balance;
        if (deallocated > 0) {
            allocated = allocated > deallocated ? allocated - deallocated : 0;
            assetToken.approve(vault, deallocated);
        }
        return deallocated;
    }

    function triggerPush(uint256 amount) external returns (bool) {
        if (shouldFail) {
            return false;
        }

        if (assetToken.balanceOf(address(this)) < amount) {
            return false;
        }

        assetToken.transfer(vault, amount);
        return true;
    }

    function pull(uint256 amount) external returns (uint256) {
        if (shouldFail) {
            return 0;
        }

        if (assetToken.balanceOf(address(this)) < amount) {
            return 0;
        }

        assetToken.transfer(vault, amount);
        return amount;
    }
}
