// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract FakeEntity {
    address public immutable FACTORY;
    uint64 public TYPE;

    uint256 public a;

    constructor(address factory, uint64 type_) {
        FACTORY = factory;
        TYPE = type_;
    }

    function setType(
        uint64 type_
    ) external returns (uint64) {
        TYPE = type_;
    }

    function setA(
        uint256 _a
    ) public {
        a = _a;
    }
}
