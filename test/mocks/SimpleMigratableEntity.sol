// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {MigratableEntity} from "src/contracts/base/MigratableEntity.sol";

contract SimpleMigratableEntity is MigratableEntity {
    uint256 public a;

    function setA(uint256 _a) public {
        a = _a;
    }

    /**
     * @inheritdoc MigratableEntity
     */
    function migrate(bytes memory) public override {
        revert();
    }
}
