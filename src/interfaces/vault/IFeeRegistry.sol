// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

uint256 constant MAX_FEE = 1_000_000;

interface IFeeRegistry {
    function getInstantWithdrawFee(address vault) external view returns (uint256 fee);
}
