// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IRegistry} from "src/interfaces/common/IRegistry.sol";

interface IDefaultOperatorRewardsDistributorFactory is IRegistry {
    /**
     * @notice Create a default operator rewards distributor for a given vault.
     * @param vault address of the vault
     * @return address of the created operator rewards distributor
     */
    function create(address vault) external returns (address);
}
