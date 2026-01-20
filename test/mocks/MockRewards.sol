// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IRewards} from "../../src/interfaces/vault/IRewards.sol";

contract MockRewards is IRewards {
    event Donate(address indexed vault, uint256 amount);

    function distributeDonationRewards(address vault, uint256 amount) external {
        emit Donate(vault, amount);
    }
}
