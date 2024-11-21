// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract RebaseToken is ERC20 {
    using Math for uint256;

    uint256 multiplier = 1000;

    constructor(
        string memory name_
    ) ERC20(name_, "") {
        uint256 amount = 1_000_000 * 1e18;
        _mint(msg.sender, amount.mulDiv(1000, multiplier));
    }

    function setMultiplier(
        uint256 multiplier_
    ) external {
        multiplier = multiplier_;
    }

    function sharesOf(
        address user
    ) public view returns (uint256) {
        return super.balanceOf(user);
    }

    function balanceOf(
        address user
    ) public view override returns (uint256) {
        return super.balanceOf(user).mulDiv(multiplier, 1000);
    }

    function transfer(address receiver, uint256 amount) public override returns (bool) {
        return super.transfer(receiver, amount.mulDiv(1000, multiplier, Math.Rounding.Ceil));
    }

    function transferFrom(address sender, address receiver, uint256 amount) public override returns (bool) {
        return super.transferFrom(sender, receiver, amount.mulDiv(1000, multiplier, Math.Rounding.Ceil));
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        return super.approve(spender, amount.mulDiv(1000, multiplier, Math.Rounding.Ceil));
    }
}
