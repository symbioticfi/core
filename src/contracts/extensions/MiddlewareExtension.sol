// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IMiddlewareExtension} from "src/interfaces/extensions/IMiddlewareExtension.sol";

import {Extension} from "src/contracts/Extension.sol";

contract MiddlewareExtension is Extension, IMiddlewareExtension {
    /**
     * @inheritdoc IMiddlewareExtension
     */
    mapping(address entity => address value) public middleware;

    constructor(address registry) Extension(registry) {}

    /**
     * @inheritdoc IMiddlewareExtension
     */
    function setMiddleware(address middleware_) external onlyEntity {
        middleware[msg.sender] = middleware_;

        emit SetMiddleware(msg.sender, middleware_);
    }
}
