// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Vault} from "./Vault.sol";
import {VaultTokenizedImplementation} from "./VaultTokenizedImplementation.sol";

import {IVaultTokenized} from "../../../interfaces/vault/v1.1.0/IVaultTokenized.sol";

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

        super._initialize(initialVersion, owner_, abi.encode(params.baseParams));

        _implementation().functionDelegateCall(
            abi.encodeWithSelector(VaultTokenizedImplementation._initialize.selector, params.name, params.symbol)
        );
    }

    function _migrate(uint64 oldVersion, uint64, /* newVersion */ bytes calldata data) internal virtual override {
        if (oldVersion == 1) {
            _implementation().functionDelegateCall(
                abi.encodeWithSelector(VaultTokenizedImplementation._initialize.selector, data)
            );
        } else if (oldVersion == 2) {} else {
            revert();
        }
    }
}
