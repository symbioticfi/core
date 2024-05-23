// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {DefaultCollateral} from "./DefaultCollateral.sol";
import {Registry} from "src/contracts/base/Registry.sol";

import {IDefaultCollateralFactory} from "src/interfaces/defaultCollateral/IDefaultCollateralFactory.sol";

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

contract DefaultCollateralFactory is Registry, IDefaultCollateralFactory {
    using Clones for address;

    address private immutable COLLATERAL_IMPLEMENTATION;

    constructor() {
        COLLATERAL_IMPLEMENTATION = address(new DefaultCollateral());
    }

    /**
     * @inheritdoc IDefaultCollateralFactory
     */
    function create(address asset, uint256 initialLimit, address limitIncreaser) external returns (address) {
        address collateral = COLLATERAL_IMPLEMENTATION.clone();
        DefaultCollateral(collateral).initialize(asset, initialLimit, limitIncreaser);

        _addEntity(collateral);

        return collateral;
    }
}
