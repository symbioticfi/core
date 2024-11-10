// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IBurner} from "../../src/interfaces/slasher/IBurner.sol";

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract SimpleBurner is IBurner {
    using SafeERC20 for IERC20;

    address public immutable COLLATERAL;

    constructor(
        address collateral
    ) {
        COLLATERAL = collateral;
    }

    uint256 public counter1;
    uint256 public counter2;
    uint256 public counter3;

    function onSlash(bytes32 subnetwork, address operator, uint256, uint48) external {
        ++counter1;
        ++counter2;
        ++counter3;
    }

    function distribute() external {
        IERC20(COLLATERAL).safeTransfer(msg.sender, IERC20(COLLATERAL).balanceOf(address(this)));
    }
}
