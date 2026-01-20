// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IRewards {
    function distributeDonationRewards(address vault, uint256 amount) external;
}
