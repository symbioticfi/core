// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IVaultDonate {
    function donate(uint256 amount) external;
}

contract Rewards is ReentrancyGuard {
    function donate(address vault, uint256 amount) external nonReentrant {
        IVaultDonate(vault).donate(amount);
    }
}
