// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IPluginBase} from "../../src/interfaces/vault/IPluginBase.sol";

contract MockPlugin is IPluginBase {
    IERC20 public immutable collateral;
    address public immutable vault;
    bool public shouldFail;

    constructor(address vault_, address collateral_) {
        vault = vault_;
        collateral = IERC20(collateral_);
    }

    function setShouldFail(bool value) external {
        shouldFail = value;
    }

    function skimmable(address vault_) external view returns (uint256) {
        if (vault_ != vault || shouldFail) {
            return 0;
        }
        return collateral.balanceOf(address(this));
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
        return collateral.balanceOf(address(this));
    }

    function allocate(uint256) external {}

    function deallocate(uint256 amount) external returns (uint256) {
        if (shouldFail) {
            return 0;
        }

        uint256 balance = collateral.balanceOf(address(this));
        uint256 deallocated = amount <= balance ? amount : balance;
        if (deallocated > 0) {
            collateral.approve(vault, deallocated);
        }
        return deallocated;
    }

    function skim(address vault_) external returns (uint256) {
        if (vault_ != vault || shouldFail) {
            return 0;
        }

        uint256 amount = collateral.balanceOf(address(this));
        if (amount > 0) {
            collateral.transfer(vault, amount);
        }
        return amount;
    }

    function triggerPush(uint256 amount) external returns (bool) {
        if (shouldFail) {
            return false;
        }

        if (collateral.balanceOf(address(this)) < amount) {
            return false;
        }

        collateral.transfer(vault, amount);
        return true;
    }

    function pull(uint256 amount) external returns (uint256) {
        if (shouldFail) {
            return 0;
        }

        if (collateral.balanceOf(address(this)) < amount) {
            return 0;
        }

        collateral.transfer(vault, amount);
        return amount;
    }
}
