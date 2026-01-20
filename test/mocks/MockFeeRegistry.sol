// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IFeeRegistry} from "../../src/interfaces/vault/IFeeRegistry.sol";

contract MockFeeRegistry is IFeeRegistry {
    uint256 public fee;

    constructor(uint256 fee_) {
        fee = fee_;
    }

    function setFlashloanFee(uint256 fee_) external {
        fee = fee_;
    }

    function getFlashloanFee(address) external view returns (uint256) {
        return fee;
    }
}
