// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {MigratableEntity} from "../../src/contracts/common/MigratableEntity.sol";

contract SimpleMigratableEntityV2 is MigratableEntity {
    uint256 public a;
    uint256 public b;

    constructor(
        address factory
    ) MigratableEntity(factory) {}

    function setA(
        uint256 a_
    ) public {
        a = a_ + 1;
    }

    function setB(
        uint256 b_
    ) public {
        b = b_;
    }

    function _migrate(uint64 oldVersion, uint64 newVersion, bytes calldata data) internal override {
        if (newVersion - oldVersion > 1) {
            revert();
        }
        uint256 b_ = abi.decode(data, (uint256));
        b = b_;
    }
}
