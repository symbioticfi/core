// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IRewards} from "../../src/interfaces/vault/IRewards.sol";
import {IVaultV2Storage} from "../../src/interfaces/vault/IVaultV2Storage.sol";

interface IVaultDonate {
    function donate(uint256 amount) external;
}

contract MockRewards is IRewards, ReentrancyGuard {
    event Donate(address indexed vault, uint256 amount);

    function donate(address vault, uint256 amount) external nonReentrant {
        IERC20 collateral = IERC20(IVaultV2Storage(vault).collateral());
        if (!collateral.transferFrom(msg.sender, address(this), amount)) {
            revert();
        }
        collateral.approve(vault, amount);
        IVaultDonate(vault).donate(amount);
    }

    function distributeDonationRewards(address vault, uint256 amount) external {
        emit Donate(vault, amount);
    }
}
