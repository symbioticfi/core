// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {IVault} from "src/interfaces/vault/IVault.sol";

interface IVaultConfigurator {
    error InvalidSlashDuration();

    struct InitParams {
        uint64 version;
        address owner;
        IVault.InitParams vaultParams;
        uint64 delegatorIndex;
        bytes delegatorParams;
        bool withSlasher;
        uint64 slasherIndex;
        bytes slasherParams;
    }

    function VAULT_FACTORY() external view returns (address);
    function DELEGATOR_FACTORY() external view returns (address);
    function SLASHER_FACTORY() external view returns (address);

    function create(InitParams memory params) external returns (address vault, address delegator, address slasher);
}
