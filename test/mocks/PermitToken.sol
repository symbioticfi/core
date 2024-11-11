// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract PermitToken is ERC20, ERC20Permit {
    constructor(
        string memory name_
    ) ERC20(name_, "") ERC20Permit(name_) {
        _mint(msg.sender, 1_000_000 * 1e18);
    }
}
