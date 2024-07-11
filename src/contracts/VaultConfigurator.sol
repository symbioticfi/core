// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {VaultFactory} from "src/contracts/VaultFactory.sol";
import {DelegatorFactory} from "src/contracts/DelegatorFactory.sol";
import {SlasherFactory} from "src/contracts/SlasherFactory.sol";
import {Vault} from "src/contracts/vault/Vault.sol";
import {BaseSlasher} from "src/contracts/slasher/BaseSlasher.sol";

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
        if (params.vaultParams.delegator != address(0) || params.vaultParams.slasher != address(0)) {
            revert DirtyInitParams();
        }

        address vault =
            VaultFactory(VAULT_FACTORY).create(params.version, params.owner, false, abi.encode(params.vaultParams));

        params.vaultParams.delegator = DelegatorFactory(DELEGATOR_FACTORY).create(
            params.delegatorIndex, true, abi.encode(vault, params.delegatorParams)
        );

        bytes memory slasherData;
        if (params.withSlasher) {
            slasherData = abi.encode(vault, params.slasherParams);
            params.vaultParams.slasher = SlasherFactory(SLASHER_FACTORY).create(params.slasherIndex, false, slasherData);
        }

        Vault(vault).initialize(params.version, params.owner, abi.encode(params.vaultParams));

        if (params.withSlasher) {
            BaseSlasher(params.vaultParams.slasher).initialize(slasherData);
        }

        return (vault, params.vaultParams.delegator, params.vaultParams.slasher);
    }
}
