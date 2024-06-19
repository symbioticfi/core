// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Slasher} from "./Slasher.sol";
import {Registry} from "src/contracts/base/Registry.sol";

import {ISlasherFactory} from "src/interfaces/slasher/v1/ISlasherFactory.sol";

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

contract SlasherFactory is Registry, ISlasherFactory {
    using Clones for address;

    address private immutable SLASHER_IMPLEMENTATION;

    constructor(
        address slasherImplementation
    ) {
        SLASHER_IMPLEMENTATION = slasherImplementation;
    }

    /**
     * @inheritdoc ISlasherFactory
     */
    function create(address vault, uint48 vetoDuration, uint48 executeDuration) external returns (address) {
        address slasher = SLASHER_IMPLEMENTATION.clone();
        Slasher(slasher).initialize(vault, vetoDuration, executeDuration);

        _addEntity(slasher);

        return slasher;
    }
}
