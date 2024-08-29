// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {IEntity} from "src/interfaces/common/IEntity.sol";
import {IEntityProxy} from "src/interfaces/common/IEntityProxy.sol";

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {Proxy} from "@openzeppelin/contracts/proxy/Proxy.sol";

contract EntityProxy is Proxy, Initializable, IEntityProxy {
    address private immutable IMPLEMENTATION;

    constructor(
        address implementation
    ) {
        IMPLEMENTATION = implementation;
    }

    /**
     * @inheritdoc Proxy
     */
    function _implementation() internal view override returns (address) {
        return IMPLEMENTATION;
    }

    /**
     * @inheritdoc Proxy
     */
    function _delegate(
        address implementation
    ) internal override {
        if (msg.sig != IEntity.initialize.selector && _getInitializedVersion() == 0) {
            revert NotInitialized();
        }

        super._delegate(implementation);
    }
}
