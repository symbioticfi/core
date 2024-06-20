// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IRegistry} from "src/interfaces/base/IRegistry.sol";

interface IDefaultStakerRewardsDistributorFactory is IRegistry {
    /**
     * @notice Create a default rewards distributor for a given vault.
     * @param vault address of the vault
     */
    function create(address vault) external returns (address);
}
