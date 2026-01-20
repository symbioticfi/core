// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IFeeRegistry {
    function getFlashloanFee(address vault) external view returns (uint256);
}
