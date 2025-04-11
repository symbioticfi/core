// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Vault} from "./Vault.sol";
import {VaultTokenizedImplementation} from "./VaultTokenizedImplementation.sol";

import {IVault} from "../../../interfaces/vault/v1.1/IVault.sol";
import {IVaultTokenized} from "../../../interfaces/vault/v1.1/IVaultTokenized.sol";

import {Address} from "@openzeppelin/contracts/utils/Address.sol";

contract VaultTokenized is Vault {
    using Address for address;

    constructor(address vaultFactory, address implementation) Vault(vaultFactory, implementation) {}

    function _initialize(uint64 initialVersion, address owner_, bytes memory data) internal virtual override {
        (IVaultTokenized.InitParamsTokenized memory params) = abi.decode(data, (IVaultTokenized.InitParamsTokenized));

        super._initialize(initialVersion, owner_, params.baseParams);

        _implementation().functionDelegateCall(
            abi.encodeCall(VaultTokenizedImplementation._VaultTokenized_init, (abi.encode(params.name, params.symbol)))
        );
    }

    function _migrate(uint64 oldVersion, uint64 newVersion, bytes memory data) internal virtual override {
        if (oldVersion == 2) {
            (IVault.MigrateParams memory params) = abi.decode(data, (IVault.MigrateParams));

            _processMigration(params);
        } else if (oldVersion == 3) {
            (IVaultTokenized.MigrateParamsTokenized memory params) =
                abi.decode(data, (IVaultTokenized.MigrateParamsTokenized));

            _implementation().functionDelegateCall(
                abi.encodeCall(
                    VaultTokenizedImplementation._VaultTokenized_init, (abi.encode(params.name, params.symbol))
                )
            );
        } else {
            revert IVault.InvalidOrigin();
        }
    }
}
