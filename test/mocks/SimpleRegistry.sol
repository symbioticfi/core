// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Registry} from "../../src/contracts/common/Registry.sol";

contract SimpleRegistry is Registry {
    function register() external returns (address) {
        _addEntity(msg.sender);
        return msg.sender;
    }
}
