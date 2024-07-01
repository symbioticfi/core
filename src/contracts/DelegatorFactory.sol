// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {Factory} from "src/contracts/common/Factory.sol";

import {IDelegatorFactory} from "src/interfaces/IDelegatorFactory.sol";

contract DelegatorFactory is Factory, IDelegatorFactory {
    constructor(address owner_) Factory(owner_) {}
}
