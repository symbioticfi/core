// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IRegistry} from "src/interfaces/base/IRegistry.sol";

interface IStakingControllerFactory is IRegistry {
    error NotVault();

    /**
     * @notice Create a staking controller.
     * @param vault - address of the vault
     */
    function create(address vault, uint48 vetoDuration, uint48 executeDuration) external returns (address);
}
