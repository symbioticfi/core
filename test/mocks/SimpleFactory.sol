// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Factory} from "src/contracts/Factory.sol";

contract SimpleFactory is Factory {
    function create() external returns (address) {
        _addEntity(msg.sender);
        return msg.sender;
    }
}
