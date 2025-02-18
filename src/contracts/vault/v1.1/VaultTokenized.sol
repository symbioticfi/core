// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Vault} from "./Vault.sol";
import {VaultTokenizedImplementation} from "./VaultTokenizedImplementation.sol";

import {IVault} from "../../../interfaces/vault/v1.1/IVault.sol";
import {IVaultTokenized} from "../../../interfaces/vault/v1.1/IVaultTokenized.sol";

import {Address} from "@openzeppelin/contracts/utils/Address.sol";

contract VaultTokenized is Vault {
    using Address for address;

    constructor(
        address delegatorFactory,
        address slasherFactory,
        address vaultFactory,
        address implementation
    ) Vault(delegatorFactory, slasherFactory, vaultFactory, implementation) {}

    function _initialize(uint64 initialVersion, address owner_, bytes memory data) internal virtual override {
        (IVaultTokenized.InitParamsTokenized memory params) = abi.decode(data, (IVaultTokenized.InitParamsTokenized));

        super._initialize(initialVersion, owner_, params.baseParams);

        _implementation().functionDelegateCall(
            abi.encodeCall(VaultTokenizedImplementation._VaultTokenized_init, (params.name, params.symbol))
        );
    }

    function _migrate(uint64 oldVersion, uint64 newVersion, bytes memory data) internal virtual override {
        if (oldVersion == 1) {
            (IVaultTokenized.MigrateParamsTokenized memory params) =
                abi.decode(data, (IVaultTokenized.MigrateParamsTokenized));

            super._migrate(oldVersion, newVersion, params.baseParams);

            _implementation().functionDelegateCall(
                abi.encodeCall(VaultTokenizedImplementation._VaultTokenized_init, (params.name, params.symbol))
            );
        } else {
            // oldVersion == 2
            super._migrate(oldVersion, newVersion, data);
        }
    }
}
