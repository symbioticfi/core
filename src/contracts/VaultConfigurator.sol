// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {VaultFactory} from "src/contracts/VaultFactory.sol";
import {DelegatorFactory} from "src/contracts/DelegatorFactory.sol";
import {SlasherFactory} from "src/contracts/SlasherFactory.sol";
import {Vault} from "src/contracts/vault/Vault.sol";

import {IVault} from "src/interfaces/vault/IVault.sol";
import {IVaultConfigurator} from "src/interfaces/IVaultConfigurator.sol";

contract VaultConfigurator is IVaultConfigurator {
    /**
     * @inheritdoc IVaultConfigurator
     */
    address public immutable VAULT_FACTORY;

    /**
     * @inheritdoc IVaultConfigurator
     */
    address public immutable DELEGATOR_FACTORY;

    /**
     * @inheritdoc IVaultConfigurator
     */
    address public immutable SLASHER_FACTORY;

    constructor(address vaultFactory, address delegatorFactory, address slasherFactory) {
        VAULT_FACTORY = vaultFactory;
        DELEGATOR_FACTORY = delegatorFactory;
        SLASHER_FACTORY = slasherFactory;
    }

    /**
     * @inheritdoc IVaultConfigurator
     */
    function create(InitParams memory params) public returns (address vault, address delegator, address slasher) {
        vault = VaultFactory(VAULT_FACTORY).create(params.version, params.owner, false, abi.encode(params.vaultParams));

        if (params.vaultParams.delegator == address(0)) {
            delegator = DelegatorFactory(DELEGATOR_FACTORY).create(
                params.delegatorIndex, true, abi.encode(vault, params.delegatorParams)
            );
        } else {
            delegator = params.vaultParams.delegator;
        }

        if (params.vaultParams.slasher == address(0)) {
            if (params.withSlasher) {
                slasher = SlasherFactory(SLASHER_FACTORY).create(
                    params.slasherIndex, true, abi.encode(vault, params.slasherParams)
                );
            }
        } else {
            slasher = params.vaultParams.slasher;
        }

        Vault(vault).initialize(
            params.version,
            params.owner,
            abi.encode(
                IVault.InitParams({
                    collateral: params.vaultParams.collateral,
                    delegator: delegator,
                    slasher: slasher,
                    burner: params.vaultParams.burner,
                    epochDuration: params.vaultParams.epochDuration,
                    slasherSetEpochsDelay: params.vaultParams.slasherSetEpochsDelay,
                    depositWhitelist: params.vaultParams.depositWhitelist,
                    defaultAdminRoleHolder: params.vaultParams.defaultAdminRoleHolder,
                    slasherSetRoleHolder: params.vaultParams.slasherSetRoleHolder,
                    depositorWhitelistRoleHolder: params.vaultParams.depositorWhitelistRoleHolder
                })
            )
        );
    }
}
