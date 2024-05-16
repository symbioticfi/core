// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Plugin} from "src/contracts/Plugin.sol";

contract SimplePlugin is Plugin {
    mapping(address entity => uint256 value) public number;

    constructor(address registry) Plugin(registry) {}

    function setNumber(uint256 number_) external onlyEntity {
        number[msg.sender] = number_;
    }
}
