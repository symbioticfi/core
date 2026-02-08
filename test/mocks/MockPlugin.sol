// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IPluginBase} from "../../src/interfaces/vault/IPluginBase.sol";

contract MockPlugin is IBasePlugin {
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
