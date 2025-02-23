// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {VaultTokenized} from "./VaultTokenized.sol";
import {VaultVotesImplementation} from "./VaultVotesImplementation.sol";

import {IVaultVotes} from "../../../interfaces/vault/v1.1/IVaultVotes.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

contract VaultVotes is VaultTokenized {
    using Address for address;

    constructor(address vaultFactory, address implementation) VaultTokenized(vaultFactory, implementation) {}

    function _initialize(uint64 initialVersion, address owner_, bytes memory data) internal virtual override {
        super._initialize(initialVersion, owner_, data);

        _implementation().functionDelegateCall(abi.encodeCall(VaultVotesImplementation._VaultVotes_init, ()));
    }

    function _migrate(uint64 oldVersion, uint64, /* newVersion */ bytes memory data) internal virtual override {
        if (oldVersion != 3) {
            revert IVaultVotes.InvalidOrigin();
        }

        if (data.length > 0) {
            revert IVaultVotes.InvalidData();
        }

        _implementation().functionDelegateCall(abi.encodeCall(VaultVotesImplementation._VaultVotes_init, ()));
    }
}
