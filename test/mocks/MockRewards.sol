// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IRewards} from "../../src/interfaces/vault/IRewards.sol";

interface IVaultDonate {
    function donate(uint256 amount) external;
}

interface IVaultCollateral {
    function collateral() external view returns (address);
}

contract MockRewards is IRewards, ReentrancyGuard {
    event Donate(address indexed vault, uint256 amount);

    uint256 public donationRewardCalls;
    address public lastDonationVault;
    uint256 public lastDonationAmount;

    function donate(address vault, uint256 amount) external nonReentrant {
        IERC20 collateral = IERC20(IVaultCollateral(vault).collateral());
        if (!collateral.transferFrom(msg.sender, address(this), amount)) {
            revert();
        }
        collateral.approve(vault, amount);
        IVaultDonate(vault).donate(amount);
    }

    function distributeDonationRewards(address vault, uint256 amount) external {
        ++donationRewardCalls;
        lastDonationVault = vault;
        lastDonationAmount = amount;
        emit Donate(vault, amount);
    }
}
