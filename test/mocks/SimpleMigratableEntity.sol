// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {MigratableEntity} from "src/contracts/common/MigratableEntity.sol";

contract SimpleMigratableEntity is MigratableEntity {
    uint256 public a;

    constructor(address factory) MigratableEntity(factory) {}

    function setA(uint256 _a) public {
        a = _a;
    }

    function _migrate(uint64, uint64, bytes calldata) internal override {
        revert();
    }
}
