// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {IPluginBase} from "../../src/interfaces/vault/IPluginBase.sol";
import {IVaultV2Storage} from "../../src/interfaces/vault/IVaultV2Storage.sol";

interface IRewardsDonate {
    function donate(address vault, uint256 amount) external;
}

contract MockMorphoAllocatePlugin is IPluginBase {
    IERC20 public immutable collateral;
    IERC4626 public immutable morphoVault;
    address public immutable vault;
    address public immutable rewards;

    constructor(address vault_, address collateral_, address morphoVault_, address rewards_) {
        vault = vault_;
        collateral = IERC20(collateral_);
        morphoVault = IERC4626(morphoVault_);
        rewards = rewards_;
    }

    function skimmable(address vault_) external view returns (uint256) {
        if (vault_ != vault) {
            return 0;
        }
        return collateral.balanceOf(address(this));
    }

    function allocatable() external pure returns (uint256) {
        return type(uint256).max;
    }

    function deallocatable(address vault_) external view returns (uint256) {
        if (vault_ != vault) {
            return 0;
        }
        return collateral.balanceOf(address(this)) + morphoVault.maxWithdraw(address(this));
    }

    function allocate(uint256 amount) external {
        if (msg.sender != vault || amount == 0) {
            return;
        }

        collateral.approve(address(morphoVault), amount);
        morphoVault.deposit(amount, address(this));
    }

    function deallocate(uint256 amount) external returns (uint256) {
        if (msg.sender != vault) {
            return 0;
        }

        skim(vault);

        if (amount == 0) {
            return 0;
        }

        uint256 balance = collateral.balanceOf(address(this));
        if (balance < amount) {
            uint256 needed = amount - balance;
            uint256 withdrawable = morphoVault.maxWithdraw(address(this));
            uint256 toWithdraw = needed <= withdrawable ? needed : withdrawable;
            if (toWithdraw > 0) {
                morphoVault.withdraw(toWithdraw, address(this), address(this));
            }
        }

        uint256 deallocated =
            amount <= collateral.balanceOf(address(this)) ? amount : collateral.balanceOf(address(this));
        if (deallocated > 0) {
            collateral.approve(vault, deallocated);
        }
        return deallocated;
    }

    function skim(address vault_) public returns (uint256) {
        if (vault_ != vault) {
            return 0;
        }

        uint256 position = collateral.balanceOf(address(this)) + morphoVault.maxWithdraw(address(this));
        uint256 allocated = IVaultV2Storage(vault).pluginAllocated(address(this));
        if (position <= allocated) {
            return 0;
        }

        uint256 amount = position - allocated;
        uint256 balance = collateral.balanceOf(address(this));
        if (balance < amount) {
            morphoVault.withdraw(amount - balance, address(this), address(this));
        }

        collateral.transfer(rewards, amount);
        IRewardsDonate(rewards).donate(vault, amount);
        return amount;
    }
}
