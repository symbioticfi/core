// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Vm} from "forge-std/Vm.sol";

import {IAdapterBase} from "../../src/interfaces/vault/IAdapterBase.sol";
import {IVaultV2} from "../../src/interfaces/vault/IVaultV2.sol";

contract MockMorphoBorrowAdapter is IAdapterBase {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    IERC20 public immutable collateral;
    IERC4626 public immutable morphoVault;
    address public immutable vault;
    address public immutable rewards;

    uint48 public borrowUnlockAt;
    uint256 public borrowedAmount;

    constructor(address vault_, address collateral_, address morphoVault_, address rewards_) {
        vault = vault_;
        collateral = IERC20(collateral_);
        morphoVault = IERC4626(morphoVault_);
        rewards = rewards_;
    }

    function allocatable(address) external view returns (uint256) {
        if (vm.getBlockTimestamp() < borrowUnlockAt) {
            return borrowedAmount < type(uint256).max ? type(uint256).max - borrowedAmount : 0;
        }
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

        if (vm.getBlockTimestamp() < borrowUnlockAt && borrowedAmount > 0) {
            return;
        }

        collateral.approve(address(morphoVault), amount);
        morphoVault.deposit(amount, address(this));
    }

    function deallocate(uint256 amount) external returns (uint256) {
        if (msg.sender != vault) {
            return 0;
        }

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
            if (deallocated >= borrowedAmount) {
                borrowedAmount = 0;
            } else {
                borrowedAmount -= deallocated;
            }
        }
        return deallocated;
    }

    function borrow(uint256 amount) external returns (uint256 borrowed) {
        if (amount == 0) {
            return 0;
        }

        uint256 remaining = amount;
        uint256 length = IVaultV2(vault).adaptersLength();
        for (uint256 i; i < length; ++i) {
            address adapter = IVaultV2(vault).adapters(i);
            if (adapter == address(this)) {
                continue;
            }

            uint256 allocated = IVaultV2(vault).adapterAllocated(adapter);
            uint256 toDeallocate = allocated <= remaining ? allocated : remaining;
            if (toDeallocate == 0) {
                continue;
            }

            uint256 deallocated = IVaultV2(vault).deallocateAdapter(adapter, toDeallocate);
            if (deallocated > 0) {
                remaining = deallocated <= remaining ? remaining - deallocated : 0;
                if (remaining == 0) {
                    break;
                }
            }
        }

        borrowed = amount - remaining;
        if (borrowed > 0) {
            borrowUnlockAt = uint48(vm.getBlockTimestamp() + 1 days);
            uint256 allocatedToThisAdapter = IVaultV2(vault).allocateAdapter(address(this), borrowed);
            borrowedAmount += allocatedToThisAdapter;
            borrowed = allocatedToThisAdapter;
        }
    }
}
