// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Factory} from "./common/Factory.sol";

import {ISlasherFactory} from "../interfaces/ISlasherFactory.sol";

contract SlasherFactory is Factory, ISlasherFactory {
    constructor(
        address owner_
    ) Factory(owner_) {}
}
