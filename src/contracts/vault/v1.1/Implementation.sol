// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {IImplementation} from "../../../interfaces/vault/v1.1/IImplementation.sol";

contract Implementation is IImplementation {
    address private immutable FACTORY;

    modifier onlyFactory() {
        _isFactory();
        _;
    }

    constructor(
        address factory
    ) {
        FACTORY = factory;
    }

    function _isFactory() internal view {
        if (msg.sender != FACTORY) {
            revert NotFactory();
        }
    }
}
