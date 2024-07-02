// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {VaultFactory} from "src/contracts/VaultFactory.sol";
import {DelegatorFactory} from "src/contracts/DelegatorFactory.sol";
import {SlasherFactory} from "src/contracts/SlasherFactory.sol";
import {Vault} from "src/contracts/vault/Vault.sol";

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
    function create(InitParams memory params) public returns (address, address, address) {
        address vault = VaultFactory(VAULT_FACTORY).create(params.version, params.owner, false, "");

        params.vaultParams.delegator = DelegatorFactory(DELEGATOR_FACTORY).create(
            params.delegatorIndex, true, abi.encode(vault, params.delegatorParams)
        );

        if (params.withSlasher) {
            params.vaultParams.slasher = SlasherFactory(SLASHER_FACTORY).create(
                params.slasherIndex, true, abi.encode(vault, params.slasherParams)
            );
        }

        Vault(vault).initialize(params.version, params.owner, abi.encode(params.vaultParams));

        return (vault, params.vaultParams.delegator, params.vaultParams.slasher);
    }
}
