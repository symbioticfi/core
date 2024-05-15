// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IFactory} from "src/interfaces/IFactory.sol";

interface IDefaultCollateralFactory is IFactory {
    /**
     * @notice Create a default collateral with a given asset.
     * @param asset address of the underlying asset
     * @param initialLimit initial limit for maximum collateral total supply
     * @param limitIncreaser address of the limit increaser (optional)
     * @return address of the created collateral
     */
    function create(address asset, uint256 initialLimit, address limitIncreaser) external returns (address);
}
