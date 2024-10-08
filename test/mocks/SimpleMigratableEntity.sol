// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {MigratableEntity} from "../../src/contracts/common/MigratableEntity.sol";

contract SimpleMigratableEntity is MigratableEntity {
    uint256 public a;

    constructor(
        address factory
    ) MigratableEntity(factory) {}

    function setA(
        uint256 _a
    ) public {
        a = _a;
    }

    function _migrate(uint64, /* oldVersion */ uint64, /* newVersion */ bytes calldata /* data */ ) internal override {
        revert();
    }
}
