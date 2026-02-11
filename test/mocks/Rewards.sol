// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IVaultDonate {
    function donate(uint256 amount) external;
}

contract Rewards {
    function donate(address vault, uint256 amount) external {
        IVaultDonate(vault).donate(amount);
    }
}
