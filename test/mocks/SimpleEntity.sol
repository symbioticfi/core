// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Entity} from "../../src/contracts/common/Entity.sol";

contract SimpleEntity is Entity {
    uint256 public a;

    constructor(address factory, uint64 type_) Entity(factory, type_) {}

    function setA(
        uint256 _a
    ) public {
        a = _a;
    }
}
