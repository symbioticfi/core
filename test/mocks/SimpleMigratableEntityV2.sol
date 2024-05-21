// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {MigratableEntity} from "src/contracts/MigratableEntity.sol";

contract SimpleMigratableEntityV2 is MigratableEntity {
    uint256 public a;
    uint256 public b;

    function setA(uint256 a_) public {
        a = a_ + 1;
    }

    function setB(uint256 b_) public {
        b = b_;
    }

    /**
     * @inheritdoc MigratableEntity
     */
    function migrate(bytes memory data) public override reinitializer(_getInitializedVersion() + 1) {
        _migrate();

        uint256 b_ = abi.decode(data, (uint256));
        b = b_;
    }
}
